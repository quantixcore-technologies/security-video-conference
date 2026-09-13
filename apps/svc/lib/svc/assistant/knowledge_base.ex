defmodule Svc.Assistant.KnowledgeBase do
  @moduledoc """
  Контент встроенного помощника (S37) — uz/ru/en.

  ПРАВИЛО: каждый ответ описывает то, что в продукте РЕАЛЬНО есть. Помощник
  без LLM не может выдумать функцию, но может её пообещать, если так написать
  в тексте, — а для B2G ложное обещание хуже отсутствия ответа. Ограничения
  (iOS не блокирует захват, видео только в нативных клиентах) проговариваем
  честно: см. D-001, D-010, D-013.
  """

  alias Svc.Assistant.Entry

  @entries [
    %Entry{
      id: :login_2fa,
      topic: :auth,
      keywords: ~w(kirish login parol 2fa totp kod tasdiq autentifikatsiya
                   вход войти пароль код подтверждение двухфакторная
                   sign password verification code two-factor),
      question: %{
        "uz" => "Tizimga qanday kiraman? 2FA kodi nima?",
        "ru" => "Как войти в систему? Что за код 2FA?",
        "en" => "How do I sign in? What is the 2FA code?"
      },
      answer: %{
        "uz" =>
          "Login va parolingizni kiriting. Agar hisobingizda ikki bosqichli tasdiqlash yoqilgan bo'lsa, keyingi qadamda autentifikator ilovasidagi 6 xonali kod so'raladi. Kodni rahbaringiz bera olmaydi — u faqat sizning telefoningizda hosil bo'ladi. Kodni yo'qotsangiz, tizim administratoriga murojaat qiling: u 2FA'ni qayta o'rnatib beradi.",
        "ru" =>
          "Введите логин и пароль. Если у учётной записи включено двухфакторное подтверждение, на следующем шаге запросится 6-значный код из приложения-аутентификатора. Код генерируется только на вашем телефоне — получить его у руководителя нельзя. Потеряли доступ к коду — обратитесь к администратору, он сбросит 2FA.",
        "en" =>
          "Enter your username and password. If two-factor verification is enabled for your account, the next step asks for a 6-digit code from your authenticator app. The code is generated only on your phone. If you lose access to it, ask your administrator to reset 2FA."
      }
    },
    %Entry{
      id: :create_meeting,
      topic: :meetings,
      # Осознанно без «yangi» / «новое» / «new» и «qo'sh» / «добавить»: это
      # надписи на кнопках, а не признак темы. С ними «yangi xodim qo'shish»
      # (добавить сотрудника) набирало столько же баллов, сколько инструкция
      # по созданию совещания, и помощник отвечал наугад.
      keywords: ~w(majlis yig'ilish uchrashuv yarat rejalash tashkil
                   совещание встреча создать запланировать организовать
                   meeting schedule organize),
      roles: [:super_admin, :manager],
      question: %{
        "uz" => "Majlisni qanday yarataman?",
        "ru" => "Как создать совещание?",
        "en" => "How do I create a meeting?"
      },
      answer: %{
        "uz" =>
          "«Majlislar» bo'limiga o'ting va «Yangi» tugmasini bosing. Sarlavha va vaqtni ko'rsating, so'ng ishtirokchilarni biriktiring. Majlis yaratish huquqi faqat rahbar (manager) va bosh administratorda bor. Takrorlanuvchi majlis kerak bo'lsa, seriya sozlamasini yoqing — tizim nusxalarini o'zi yaratadi.",
        "ru" =>
          "Откройте раздел «Совещания» и нажмите «Новое». Укажите название и время, затем прикрепите участников. Создавать совещания могут только руководитель (manager) и главный администратор. Нужна серия — включите повторение, система создаст копии сама.",
        "en" =>
          "Open the Meetings section and click New. Set a title and time, then attach participants. Only a manager or the super administrator can create meetings. For a recurring series, enable repetition and the system creates the copies for you."
      }
    },
    %Entry{
      id: :join_call,
      topic: :meetings,
      keywords: ~w(qo'ng'iroq video ulanish qo'shil kirish efir kamera qatnash
                   звонок видео подключиться присоединиться войти эфир камера
                   call video join connect),
      question: %{
        "uz" => "Video qo'ng'iroqqa qanday qo'shilaman?",
        "ru" => "Как подключиться к видеозвонку?",
        "en" => "How do I join a video call?"
      },
      answer: %{
        "uz" =>
          "Majlis kartochkasini oching va «Qo'shilish» tugmasini bosing. Video faqat nativ klientlarda ishlaydi — Android ilovasi yoki Windows uchun desktop dasturi; brauzerdagi panel boshqaruv uchun mo'ljallangan. Birinchi ulanishda kamera va mikrofonga ruxsat so'raladi. Qo'shila olmasangiz, sizni o'sha majlisga biriktirishganini tekshiring: biriktirilmagan xodim yopiq majlisni umuman ko'rmaydi.",
        "ru" =>
          "Откройте карточку совещания и нажмите «Подключиться». Видео работает только в нативных клиентах — приложение Android или десктоп под Windows; веб-панель предназначена для управления. При первом подключении запрашивается доступ к камере и микрофону. Если подключиться не удаётся, проверьте, что вас прикрепили к этому совещанию: непричастный сотрудник закрытое совещание вообще не видит.",
        "en" =>
          "Open the meeting card and press Join. Video works only in the native clients — the Android app or the Windows desktop app; the web panel is for management. On first connect you are asked for camera and microphone access. If you cannot join, check that you were attached to that meeting: closed meetings are invisible to people who were not invited."
      }
    },
    %Entry{
      id: :meeting_privacy,
      topic: :meetings,
      keywords: ~w(maxfiy yopiq ko'rinmaydi kim ko'radi huquq ruxsat rbac rol
                   закрытое конфиденциальное невидно кто видит права роль доступ
                   private confidential visibility who sees permission role),
      question: %{
        "uz" => "Majlisni kim ko'ra oladi? Nega ro'yxatda ko'rinmayapti?",
        "ru" => "Кто видит совещание? Почему его нет в списке?",
        "en" => "Who can see a meeting? Why is it missing from my list?"
      },
      answer: %{
        "uz" =>
          "Majlisni faqat uni tashkil qilgan shaxs va biriktirilgan ishtirokchilar ko'radi. Bu ataylab shunday: boshqa rahbarning yopiq majlisi bosh administratorga ham ko'rinmaydi. Agar majlis ro'yxatingizda yo'q bo'lsa — sizni unga biriktirishmagan; tashkilotchidan qo'shishni so'rang.",
        "ru" =>
          "Совещание видят только организатор и прикреплённые участники. Так задумано: закрытое совещание одного руководителя не видно даже главному администратору. Нет совещания в списке — значит вас к нему не прикрепили; попросите организатора добавить вас.",
        "en" =>
          "A meeting is visible only to its organizer and the attached participants. This is deliberate: one manager's closed meeting is not visible even to the super administrator. If a meeting is missing from your list, you were not attached to it — ask the organizer to add you."
      }
    },
    %Entry{
      id: :tasks,
      topic: :tasks,
      keywords: ~w(topshiriq vazifa kanban doska muddat ijrochi status
                   поручение задача канбан доска срок исполнитель статус
                   task assignment kanban board deadline assignee),
      question: %{
        "uz" => "Topshiriqlar bilan qanday ishlayman?",
        "ru" => "Как работать с поручениями?",
        "en" => "How do I work with tasks?"
      },
      answer: %{
        "uz" =>
          "«Topshiriqlar» bo'limi — to'rt ustunli kanban doskasi. Kartochkani sichqoncha bilan bir ustundan boshqasiga tortib holatini o'zgartirasiz. Topshiriqni to'g'ridan-to'g'ri majlisdan ham yaratish mumkin — majlis kartochkasidagi tegishli tugma orqali; unda kartochkada majlis belgisi qoladi va ijrochiga bildirishnoma boradi. Muddati o'tgan topshiriqlar alohida ajratib ko'rsatiladi.",
        "ru" =>
          "Раздел «Поручения» — канбан-доска из четырёх колонок. Статус меняется перетаскиванием карточки между колонками. Поручение можно создать прямо из совещания — кнопкой на его карточке; тогда на карточке остаётся метка совещания, а исполнителю уходит уведомление. Просроченные поручения выделяются отдельно.",
        "en" =>
          "The Tasks section is a four-column kanban board. Change status by dragging a card between columns. You can also create a task straight from a meeting using the button on its card; the card then keeps a meeting badge and the assignee gets a notification. Overdue tasks are highlighted separately."
      }
    },
    %Entry{
      id: :calendar_reminders,
      topic: :meetings,
      keywords: ~w(kalendar taqvim eslatma eslat ics outlook google export rsvp
                   календарь напоминание напомнить экспорт приду
                   calendar reminder export invite rsvp),
      question: %{
        "uz" => "Kalendar, eslatmalar va .ics eksporti qanday ishlaydi?",
        "ru" => "Как работают календарь, напоминания и экспорт .ics?",
        "en" => "How do the calendar, reminders and .ics export work?"
      },
      answer: %{
        "uz" =>
          "«Kalendar» bo'limi majlislarni oylik ko'rinishda ko'rsatadi. Tizim eslatmalarni avtomatik yuboradi — majlisdan 24 soat va 1 soat oldin. Har bir majlis kartochkasida ishtirokni tasdiqlash tugmalari bor: kelaman / ehtimol / kelmayman. Majlisni Outlook yoki Google Calendar'ga o'tkazish uchun .ics faylini yuklab oling.",
        "ru" =>
          "Раздел «Календарь» показывает совещания в виде месяца. Напоминания уходят автоматически — за 24 часа и за 1 час до начала. На карточке совещания есть кнопки ответа: приду / возможно / не приду. Чтобы перенести совещание в Outlook или Google Calendar, скачайте файл .ics.",
        "en" =>
          "The Calendar section shows meetings in a month view. Reminders are sent automatically — 24 hours and 1 hour before the start. Each meeting card has RSVP buttons: yes / maybe / no. To move a meeting into Outlook or Google Calendar, download the .ics file."
      }
    },
    %Entry{
      id: :notifications,
      topic: :notifications,
      keywords: ~w(bildirishnoma xabar qo'ng'iroqcha o'qilgan
                   уведомление оповещение колокольчик прочитано
                   notification bell unread),
      question: %{
        "uz" => "Bildirishnomalarni qayerdan ko'raman?",
        "ru" => "Где смотреть уведомления?",
        "en" => "Where do I see notifications?"
      },
      answer: %{
        "uz" =>
          "Yuqori panelda qo'ng'iroqcha belgisi bor — o'qilmagan bildirishnomalar soni shunda ko'rinadi. Uni bosib to'liq ro'yxatga o'tasiz va hammasini bir marta o'qilgan deb belgilay olasiz. Bildirishnomalar majlis eslatmalari, yangi topshiriqlar va xavfsizlik hodisalari bo'yicha keladi.",
        "ru" =>
          "В верхней панели есть колокольчик — на нём видно число непрочитанных. По клику открывается полный список, где можно отметить все как прочитанные. Уведомления приходят о напоминаниях по совещаниям, новых поручениях и событиях безопасности.",
        "en" =>
          "The top bar has a bell icon showing the unread count. Clicking it opens the full list, where you can mark everything as read. Notifications cover meeting reminders, new tasks and security events."
      }
    },
    %Entry{
      id: :manage_users,
      topic: :admin,
      keywords: ~w(xodim foydalanuvchi qo'sh yarat rol o'zgartir bo'lim kadr
                   сотрудник пользователь добавить создать роль изменить отдел
                   user employee add create role change department),
      roles: [:super_admin, :admin_hr],
      question: %{
        "uz" => "Yangi xodimni qanday qo'shaman?",
        "ru" => "Как добавить нового сотрудника?",
        "en" => "How do I add a new employee?"
      },
      answer: %{
        "uz" =>
          "«Xodimlar» bo'limiga o'ting va «Yangi» tugmasini bosing. Ism, login, boshlang'ich parol va rolni ko'rsating. Rollar: bosh administrator, kadrlar, rahbar, xodim, xavfsizlik bo'yicha mas'ul — ular kim nima qila olishini belgilaydi. Xodim kartochkasida keyinchalik ikki bosqichli tasdiqlashni yoqish yoki qayta o'rnatish mumkin. Foydalanuvchilarni boshqarish huquqi faqat bosh administrator va kadrlar bo'limida.",
        "ru" =>
          "Откройте раздел «Сотрудники» и нажмите «Новый». Укажите имя, логин, стартовый пароль и роль. Роли: главный администратор, кадры, руководитель, сотрудник, ответственный за безопасность — они определяют, кому что доступно. В карточке сотрудника позже можно включить или сбросить двухфакторное подтверждение. Управлять пользователями могут только главный администратор и кадры.",
        "en" =>
          "Open the Employees section and click New. Set the name, username, initial password and role. The roles — super administrator, HR, manager, employee, security officer — decide what each person can do. From the employee card you can later enable or reset two-factor verification. Only the super administrator and HR can manage users."
      }
    },
    %Entry{
      id: :security_log,
      topic: :security,
      keywords: ~w(xavfsizlik jurnal skrinshot ekran yozib olish rekorder hodisa
                   безопасность журнал скриншот запись экрана рекордер событие захват
                   security log screenshot recording recorder capture event),
      roles: [:super_admin, :manager, :security_officer],
      question: %{
        "uz" => "Ekranni yozib olish urinishlarini qayerdan ko'raman?",
        "ru" => "Где смотреть попытки захвата экрана?",
        "en" => "Where do I see screen capture attempts?"
      },
      answer: %{
        "uz" =>
          "«Xavfsizlik» bo'limida hodisalar jurnali bor: skrinshot urinishlari, ekran yozib oluvchi dasturlar va geolokatsiya tekshiruvlari. Har bir majlis uchun reaksiyani alohida sozlash mumkin — hech narsa qilmaslik, ogohlantirish yoki ishtirokchini majlisdan chiqarib yuborish. Muhim cheklov: yozib olishni Windows va Android'da bloklash mumkin, iOS'da esa faqat aniqlanadi. Telefonda ekranni suratga olishni esa hech qanday dastur to'sa olmaydi — shuning uchun har bir kadrga foydalanuvchi izi (watermark) tushiriladi.",
        "ru" =>
          "В разделе «Безопасность» есть журнал событий: попытки скриншота, программы записи экрана и гео-проверки. Реакция настраивается для каждого совещания отдельно — ничего, предупреждение или удаление участника. Важное ограничение: блокировать запись можно на Windows и Android, на iOS она только детектируется. Съёмку экрана телефоном не предотвратит ничто — поэтому на каждый кадр наносится водяной знак с данными пользователя.",
        "en" =>
          "The Security section holds the event log: screenshot attempts, screen-recording software and geo checks. The reaction is configured per meeting — nothing, warn, or eject the participant. An important limit: capture can be blocked on Windows and Android, on iOS it can only be detected. Nothing can stop someone filming the screen with a phone — which is why every frame carries a watermark identifying the viewer."
      }
    },
    %Entry{
      id: :screen_share,
      topic: :meetings,
      keywords: ~w(ekran namoyish ulash ko'rsat demonstratsiya share
                   экран демонстрация показать поделиться шаринг
                   screen share sharing present),
      question: %{
        "uz" => "Ekranimni qanday ko'rsataman?",
        "ru" => "Как показать свой экран?",
        "en" => "How do I share my screen?"
      },
      answer: %{
        "uz" =>
          "Qo'ng'iroq paytida boshqaruv panelidagi ekran namoyishi tugmasini bosing. Android'da tizim ruxsat so'raydi — tasdiqlang. Ekran namoyishi boshqa ishtirokchilarga ko'zgu qilinmagan holda, ya'ni asl ko'rinishda uzatiladi, shuning uchun yozuvlar o'qilaveradi. Namoyishni to'xtatish uchun xuddi shu tugmani qayta bosing.",
        "ru" =>
          "Во время звонка нажмите кнопку демонстрации экрана на панели управления. На Android система запросит разрешение — подтвердите его. Демонстрация передаётся другим участникам без зеркалирования, в исходном виде, поэтому текст остаётся читаемым. Чтобы остановить, нажмите ту же кнопку ещё раз.",
        "en" =>
          "During a call press the screen-share button on the control bar. On Android the system asks for permission — confirm it. The shared screen reaches the other participants unmirrored, so text stays readable. Press the same button again to stop sharing."
      }
    },
    %Entry{
      id: :mobile_app,
      topic: :clients,
      keywords: ~w(android ilova apk telefon mobil yuklab o'rnat yangilanish
                   андроид приложение телефон мобильное скачать установить обновление
                   mobile app download install update),
      question: %{
        "uz" => "Android ilovasini qayerdan olaman va qanday yangilayman?",
        "ru" => "Где взять приложение для Android и как его обновить?",
        "en" => "Where do I get the Android app and how do I update it?"
      },
      answer: %{
        "uz" =>
          "Ilovani tashkilotimiz sayti orqali yuklab olasiz — Play Market'da yo'q, chunki u ichki foydalanish uchun. Yangilanish ilovaning o'zi ichida bo'ladi: yangi versiya chiqsa, ilova buni aytadi va o'zi yuklab olib o'rnatadi, brauzer ham, do'kon ham kerak emas. Ba'zi yangilanishlar majburiy — eski versiya yopiq majlislarga ulanmasligi uchun.",
        "ru" =>
          "Приложение скачивается с сайта организации — в Play Market его нет, оно для внутреннего использования. Обновление происходит внутри приложения: при выходе новой версии оно само предложит, скачает и установит её, без браузера и магазина. Часть обновлений обязательные — чтобы устаревший клиент не подключался к закрытым совещаниям.",
        "en" =>
          "The app is downloaded from the organisation's site — it is not on the Play Store because it is for internal use. Updates happen inside the app: when a new version appears it offers, downloads and installs it without a browser or store. Some updates are mandatory, so that an outdated client cannot join closed meetings."
      }
    },
    %Entry{
      id: :language,
      topic: :profile,
      keywords: ~w(til tilni o'zgartir o'zbek rus ingliz interfeys
                   язык сменить узбекский русский английский интерфейс
                   language switch change uzbek russian english interface),
      question: %{
        "uz" => "Interfeys tilini qanday o'zgartiraman?",
        "ru" => "Как сменить язык интерфейса?",
        "en" => "How do I change the interface language?"
      },
      answer: %{
        "uz" =>
          "Yuqori panelda til almashtirgich bor — o'zbek, rus va ingliz tillari mavjud. Tanlov saqlanadi va keyingi kirishlaringizda ham o'sha tilda ochiladi.",
        "ru" =>
          "В верхней панели есть переключатель языка — доступны узбекский, русский и английский. Выбор сохраняется и применяется при следующих входах.",
        "en" =>
          "The top bar has a language switcher with Uzbek, Russian and English. Your choice is saved and applied on later sign-ins."
      }
    },
    %Entry{
      id: :profile_password,
      topic: :profile,
      keywords: ~w(profil parol o'zgartir yangila rasm ma'lumot shaxsiy
                   профиль пароль сменить обновить личные данные
                   profile password change update personal),
      question: %{
        "uz" => "Parolimni va profil ma'lumotlarimni qanday o'zgartiraman?",
        "ru" => "Как сменить пароль и данные профиля?",
        "en" => "How do I change my password and profile details?"
      },
      answer: %{
        "uz" =>
          "O'ng yuqori burchakdagi avatarni bosing va «Profil» bo'limiga o'ting. U yerda ism va aloqa ma'lumotlarini yangilash, parolni o'zgartirish va ikki bosqichli tasdiqlashni yoqish mumkin. Parolni o'zgartirishda uni ikki marta kiritish so'raladi.",
        "ru" =>
          "Нажмите на аватар в правом верхнем углу и откройте «Профиль». Там можно обновить имя и контакты, сменить пароль и включить двухфакторное подтверждение. При смене пароля его нужно ввести дважды.",
        "en" =>
          "Click your avatar in the top-right corner and open Profile. There you can update your name and contacts, change your password and enable two-factor verification. Changing the password requires entering it twice."
      }
    },
    %Entry{
      id: :geo_check,
      topic: :security,
      keywords: ~w(joylashuv geo gps mamlakat tekshiruv ruxsat bermadi bloklandi
                   геолокация местоположение страна проверка не пускает блокировка
                   location geo country check blocked denied),
      question: %{
        "uz" => "Nega meni majlisga qo'shmadi — joylashuv tekshiruvi nima?",
        "ru" => "Почему меня не пустило на совещание — что за гео-проверка?",
        "en" => "Why was I refused entry — what is the geo check?"
      },
      answer: %{
        "uz" =>
          "Majlisga ulanishdan oldin tizim tarmoq va joylashuvni tekshiradi: tashkilot siyosati qaysi mamlakatlardan ulanishga ruxsat berishini belgilaydi. Telefonda joylashuvga ruxsat bermagan bo'lsangiz, ilova koordinatasiz ulanadi — bu ba'zi siyosatlarda rad etilishi mumkin. Ruxsat berishda «taxminiy» ni tanlasangiz ham yetarli. Rad etilsangiz, sabab xavfsizlik jurnalida qayd etiladi — administratordan tekshirishni so'rang.",
        "ru" =>
          "Перед подключением система проверяет сеть и местоположение: политика организации задаёт, из каких стран разрешён вход. Если вы не дали приложению доступ к геолокации, подключение идёт без координат — часть политик это отклоняет. Достаточно выбрать «приблизительно». При отказе причина записывается в журнал безопасности — попросите администратора посмотреть.",
        "en" =>
          "Before connecting, the system checks the network and location: your organisation's policy decides which countries may connect from. If you did not grant the app location access, the join goes without coordinates, which some policies reject. Choosing approximate location is enough. When entry is refused the reason is written to the security log — ask your administrator to check it."
      }
    }
  ]

  @doc "Все записи базы знаний."
  def entries, do: @entries

  @doc "Записи, доступные роли (nil — только публичные)."
  def entries_for(role), do: Enum.filter(@entries, &Entry.visible?(&1, role))

  @doc "Список тем, встречающихся в базе (для чипов-подсказок в UI)."
  def topics, do: @entries |> Enum.map(& &1.topic) |> Enum.uniq()
end
