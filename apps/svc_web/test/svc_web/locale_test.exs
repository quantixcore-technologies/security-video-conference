defmodule SvcWeb.LocaleTest do
  @moduledoc "i18n: локаль-плаг, on_mount и переводы (uz/ru/en). БД не требуется."
  use ExUnit.Case, async: true

  import Plug.Test

  alias SvcWeb.Locale

  describe "supported/default/label" do
    test "supported locales and default" do
      assert Locale.supported() == ~w(uz ru en)
      assert Locale.default() == "ru"
    end

    test "human labels" do
      assert Locale.label("uz") == "O'zbekcha"
      assert Locale.label("ru") == "Русский"
      assert Locale.label("en") == "English"
    end
  end

  describe "plug call/2" do
    test "берёт локаль из сессии, ставит Gettext-локаль и assign" do
      conn =
        conn(:get, "/")
        |> init_test_session(%{locale: "uz"})
        |> Locale.call([])

      assert conn.assigns.locale == "uz"
      assert Gettext.get_locale(SvcWeb.Gettext) == "uz"
    end

    test "неизвестная локаль → дефолт ru" do
      conn =
        conn(:get, "/")
        |> init_test_session(%{locale: "fr"})
        |> Locale.call([])

      assert conn.assigns.locale == "ru"
    end

    test "нет локали в сессии → дефолт ru" do
      conn = conn(:get, "/") |> init_test_session(%{}) |> Locale.call([])
      assert conn.assigns.locale == "ru"
    end
  end

  describe "on_mount/4" do
    test "ставит локаль в socket assigns из сессии" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      {:cont, socket} = Locale.on_mount(:default, %{}, %{"locale" => "en"}, socket)
      assert socket.assigns.locale == "en"
      assert Gettext.get_locale(SvcWeb.Gettext) == "en"
    end
  end

  describe "translations" do
    test "uz — узбекский перевод навигации" do
      Gettext.put_locale(SvcWeb.Gettext, "uz")
      assert Gettext.gettext(SvcWeb.Gettext, "Панель") == "Boshqaruv paneli"
      assert Gettext.gettext(SvcWeb.Gettext, "Встречи") == "Uchrashuvlar"
      assert Gettext.gettext(SvcWeb.Gettext, "Безопасность") == "Xavfsizlik"
    end

    test "en — английский перевод" do
      Gettext.put_locale(SvcWeb.Gettext, "en")
      assert Gettext.gettext(SvcWeb.Gettext, "Панель") == "Dashboard"
      assert Gettext.gettext(SvcWeb.Gettext, "Выйти") == "Log out"
    end

    test "ru — исходный язык (fallback к msgid)" do
      Gettext.put_locale(SvcWeb.Gettext, "ru")
      assert Gettext.gettext(SvcWeb.Gettext, "Панель") == "Панель"
    end
  end
end
