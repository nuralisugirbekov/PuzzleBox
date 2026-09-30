# Firebase Analytics

Подключён Firebase Apple SDK 12.x через Swift Package Manager: FirebaseCore и FirebaseAnalytics. Xcode загрузит зависимости при открытии проекта. GoogleService-Info.plist включён в автоматически синхронизируемую папку основного target. Bundle ID совпадает с конфигурацией Firebase: com.nurali.PuzzleBoxApp.

Firebase настраивается в FirebaseAppDelegate до отображения экранов. Автоматический сбор screen_view отключён: SwiftUI-экраны отправляются явно. Сбор IDFA отключён. Сырые поисковые запросы и содержимое партий не передаются.

## События

- `screen_view`: `main_menu`, `language_selection`, `game_<game_id>`.
- `language_selected`: подтверждение нового языка; `app_language`, `previous_language`, `selection_source` (`onboarding` или `settings`). Повторное подтверждение того же языка не создаёт событие.
- `select_content`: выбор игры; `content_type=game`, `item_id`, `selection_source` (`grid`, `search`, `random`).
- `category_selected`: смена фильтра; `game_category` или `all`.
- `level_start`: начало каждой партии, в том числе после перезапуска.
- `game_pause`, `game_resume`: ручная пауза и продолжение; текущий `score`.
- `game_restart`: новый раунд; `game_id`, `restart_source` (`header`, `pause`, `game_over`).
- `level_end`: завершение партии; `score`, `success` (1 при победе, иначе 0), `end_reason` (`completed`, `restart`, `exit`), `duration_seconds`, `new_high_score` (0/1). Для процента побед фильтруйте `end_reason=completed`.
- `post_score`: счёт завершённой партии; `game_id`, `score`.
- `new_high_score`: новый локальный рекорд после завершённой партии; `game_id`, `score`.

События раунда содержат `game_id`, `level_name`, `game_category`, `difficulty`. Идентификаторы не зависят от языка интерфейса. `duration_seconds` считает активное время монотонными часами, исключая паузу и неактивное состояние приложения. На завершённую партию отправляется одно `level_end`; выход с экрана результатов не дублирует его. Принудительное закрытие процесса не гарантирует событие выхода.

Все события содержат `app_language` (`ru`, `kk`, `en`, до выбора — `not_selected`). Выбранный язык также записывается в одноимённое пользовательское свойство. Стандартные события установки и сессий собирает SDK.

## Настройка в Firebase Console

В Firebase Console проекта puzzlebox-ea9b9 Google Analytics включён (подтверждено пользователем). Значение `IS_ANALYTICS_ENABLED=false` в GoogleService-Info.plist не отключает сбор: Firebase относит этот ключ к неиспользуемым полям. Файл оставлен без изменений. Сбор в приложении управляется `FIREBASE_ANALYTICS_COLLECTION_ENABLED` в Info.plist (установлено true) и методом `Analytics.setAnalyticsCollectionEnabled(_:)`, если он вызывается.

Источник: https://github.com/firebase/firebase-ios-sdk/blob/main/docs/FirebaseOptionsPerProduct.md#unread-googleservice-infoplist-fields

Для использования пользовательских параметров в обычных отчётах GA4 зарегистрируйте нужные параметры как custom dimensions, а `duration_seconds` — как custom metric. Обычно достаточно `game_id`, `game_category`, `difficulty`, `selection_source`, `end_reason`, `app_language`.

Для ручной проверки добавьте `-FIRDebugEnabled` в Xcode → Scheme → Run → Arguments и откройте Analytics → DebugView. Затем выберите язык, откройте игру, поставьте паузу, продолжите, перезапустите и выйдите. Аргумент предназначен для отладки; для отключения используйте `-FIRDebugDisabled`.

Сборка, разрешение зависимостей, запуск приложения и отправка событий в DebugView в рамках изменения не выполнялись по просьбе пользователя.

Документация Firebase:
- https://firebase.google.com/docs/ios/setup
- https://firebase.google.com/docs/analytics/ios/events
- https://firebase.google.com/docs/analytics/debugview
