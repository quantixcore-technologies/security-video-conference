defmodule Svc.AssistantTest do
  @moduledoc """
  S37: встроенный помощник без LLM. Тесты бьют по двум вещам, которые ломают
  такой помощник на практике: качество сопоставления (морфология, стоп-слова)
  и честность (не отвечать наугад, не показывать недоступное по роли).
  """
  use ExUnit.Case, async: true

  alias Svc.Assistant
  alias Svc.Assistant.{Entry, KnowledgeBase}

  describe "ask/2 — попадание в тему" do
    test "узбекский вопрос про создание совещания" do
      assert {:ok, entry, _related} = Assistant.ask("majlisni qanday yarataman?", role: :manager)
      assert entry.id == :create_meeting
    end

    test "русский вопрос про подключение к звонку" do
      assert {:ok, entry, _} = Assistant.ask("как подключиться к видеозвонку", role: :employee)
      assert entry.id == :join_call
    end

    test "английский вопрос про 2FA" do
      assert {:ok, entry, _} =
               Assistant.ask("where do I get the two-factor code?", role: :employee)

      assert entry.id == :login_2fa
    end

    test "смешанный uz+ru вопрос — так реально пишут" do
      assert {:ok, entry, _} =
               Assistant.ask("скриншот urinishlari jurnali", role: :security_officer)

      assert entry.id == :security_log
    end
  end

  describe "ask/2 — морфология" do
    # Узбекский агглютинативен: «majlis» → «majlisni», «majlisga», «majlislar».
    # Точное сравнение токенов ловило бы только словарную форму.
    test "узбекские падежные формы находят ту же запись" do
      for form <- ~w(majlis majlisni majlisga majlislar majlisingiz) do
        assert {:ok, %Entry{id: :create_meeting}, _} =
                 Assistant.ask("#{form} yaratish", role: :manager),
               "forma #{form} topilmadi"
      end
    end

    test "русские склонения находят ту же запись" do
      for form <- ~w(совещание совещания совещанию совещаний) do
        assert {:ok, %Entry{id: :create_meeting}, _} =
                 Assistant.ask("создать #{form}", role: :manager),
               "форма #{form} не найдена"
      end
    end
  end

  describe "ask/2 — честность" do
    test "пустой и бессмысленный ввод не выдаёт случайный ответ" do
      for query <- ["", "   ", "?!.", "как мне что где"] do
        assert {:no_match, suggestions} = Assistant.ask(query, role: :employee)
        assert suggestions != [], "подсказки должны быть всегда"
      end
    end

    test "вопрос не по теме продукта → no_match, а не выдуманный ответ" do
      assert {:no_match, _} = Assistant.ask("какая завтра погода в Ташкенте", role: :employee)
    end

    # Ключевая защита: одни стоп-слова не должны никуда попадать. Без их отсева
    # «как мне сделать» матчилось бы со всем подряд и первый ответ был бы случайным.
    test "одни только стоп-слова не дают совпадения" do
      assert {:no_match, _} = Assistant.ask("qanday qilaman bu nima uchun kerak", role: :manager)
    end
  end

  describe "ask/2 — фильтр по ролям (D-016)" do
    # Не «спрятать», а объяснить: сотрудник должен понять, что действие
    # существует, но требует другой роли. Молчание он читает как поломку.
    test "сотруднику честно говорят, что управление пользователями ему недоступно" do
      assert {:restricted, %Entry{id: :manage_users}} =
               Assistant.ask("yangi xodim qo'shish", role: :employee)
    end

    test "главному администратору — полный ответ" do
      assert {:ok, %Entry{id: :manage_users}, _} =
               Assistant.ask("yangi xodim qo'shish", role: :super_admin)
    end

    test "создание совещания: сотруднику — restricted, руководителю — ответ" do
      # can_organize? — только super_admin и manager (Svc.Meetings).
      assert {:restricted, %Entry{id: :create_meeting}} =
               Assistant.ask("majlis yaratish", role: :employee)

      assert {:ok, %Entry{id: :create_meeting}, _} =
               Assistant.ask("majlis yaratish", role: :manager)
    end

    test "в related и unsure недоступные роли записи не утекают" do
      for role <- [:employee, :manager, :security_officer, nil] do
        case Assistant.ask("majlis qo'ng'iroq xavfsizlik", role: role) do
          {:ok, entry, related} ->
            assert Entry.visible?(entry, role)
            assert Enum.all?(related, &Entry.visible?(&1, role))

          {:unsure, candidates} ->
            assert Enum.all?(candidates, &Entry.visible?(&1, role))

          {:restricted, _} ->
            :ok

          {:no_match, suggestions} ->
            assert Enum.all?(suggestions, &Entry.visible?(&1, role))
        end
      end
    end

    test "без роли доступны только записи для всех" do
      for entry <- KnowledgeBase.entries_for(nil) do
        assert entry.roles == :all
      end
    end
  end

  describe "база знаний" do
    test "у каждой записи есть все три языка и в вопросе, и в ответе" do
      for entry <- KnowledgeBase.entries(), field <- [:question, :answer] do
        map = Map.fetch!(entry, field)

        for lang <- ~w(uz ru en) do
          text = Map.get(map, lang)

          assert is_binary(text) and String.trim(text) != "",
                 "#{entry.id}.#{field} — #{lang} bo'sh"
        end
      end
    end

    test "идентификаторы уникальны" do
      ids = Enum.map(KnowledgeBase.entries(), & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "у каждой записи есть ключевые слова на всех трёх языках" do
      # Иначе вопрос на одном из языков молча не находится.
      for entry <- KnowledgeBase.entries() do
        assert length(entry.keywords) >= 6, "#{entry.id}: kalit so'zlar juda kam"
      end
    end

    test "fetch/2 уважает роль" do
      assert {:ok, %Entry{id: :manage_users}} = Assistant.fetch(:manage_users, role: :super_admin)
      assert :error = Assistant.fetch(:manage_users, role: :employee)
      assert :error = Assistant.fetch(:nosuch_entry, role: :super_admin)
    end
  end

  describe "Entry.text/2" do
    test "возвращает нужный язык, а при его отсутствии — узбекский" do
      map = %{"uz" => "salom", "ru" => "привет"}
      assert Entry.text(map, "ru") == "привет"
      assert Entry.text(map, "uz") == "salom"
      assert Entry.text(map, "en") == "salom"
    end
  end

  describe "suggestions/1" do
    test "непустые и отфильтрованы по роли" do
      assert Assistant.suggestions(role: :employee) != []

      for entry <- Assistant.suggestions(role: :employee) do
        assert Entry.visible?(entry, :employee)
      end
    end
  end
end
