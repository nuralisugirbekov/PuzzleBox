# PuzzleBox

Сборник из 52 казуальных игр для iPhone: логические головоломки, японские пазлы, пасьянсы, аркады, физические мини-игры и тренажёры реакции. Интерфейс на SwiftUI в стиле Apple Music, светлая и тёмная темы, 8 языков.

## Игры

| Категория | Игры |
|---|---|
| **Logic** | Arrow Escape, Block Blast, Water Sort, Minesweeper, Checkmate, Lights Out, One Line, Unblock, 15 Puzzle, Pipe Connect, Dots, Flood Fill, Laser, Color Lines |
| **Japanese puzzles** | Sudoku (6×6 и 9×9), Nonogram, Numberlink |
| **Numbers** | 2048, Quick Math, Matchstick Puzzle |
| **Cards** | Solitaire (Klondike), Spider, FreeCell |
| **Arcade** | Rocket Maze, Bounce, Snake, Stack, Knife Spin, Helix Drop, Flappy Flight, Road Hop, Slope, Circle Pong, Space Dodge, Endless Climb, Chain Reaction |
| **Physics** | Merge Fruit, Basket Shot, Bottle Flip, Golf, Plinko, Rope Cut, Draw Bridge |
| **Reaction** | Reaction Tap, Simon, Red Light Green Light, Perfect Timing, Bubble Pop, Whack-a-Mole |
| **Attention** | Find the Color, Find the Pair |
| **Visual puzzles** | Rotate Puzzle |

Некоторые игры:

- **Arrow Escape** — 100 сгенерированных уровней от 15×20 до 44×58 клеток; каждый уровень гарантированно решаем. Подробнее: [docs/arrow-escape.md](docs/arrow-escape.md).
- **Rocket Maze** — лабиринт на SpriteKit: ракета движется непрерывно, игрок поворачивает её и собирает звёзды. Подробнее: [docs/arrow-maze.md](docs/arrow-maze.md).
- **Checkmate** — 306 задач «мат в один ход» (`Resources/MateInOne.json`).
- **Merge Fruit** — физика на SpriteKit.

## Возможности

- Пять вкладок: **Главная** (игра дня, подборки, недавние, популярные), **Обзор** (полки по категориям, «Быстро и просто», все игры), **Рейтинг** (личные рекорды и статистика), **Мои игры** (избранное), **Поиск**.
- Кнопка **Random Game**. С экрана результатов можно сразу перейти в случайную игру, не возвращаясь в меню.
- Общий игровой контейнер: счёт, рекорд, пауза, перезапуск, экран результатов с конфетти.
- Экран «Как играть» с правилами и управлением; при первом запуске игры он открывается сам.
- Звуки генерируются кодом через AVFoundation, без аудиофайлов. Есть тактильная отдача.
- Настройки: тема (авто/светлая/тёмная), язык, звук, вибрация.
- Языки: русский, казахский, английский, французский, хинди, немецкий, упрощённый китайский, корейский. Язык выбирается при первом запуске.
- Рекорды, избранное и история хранятся локально в `UserDefaults`.
- Firebase Analytics: события выбора игры, начала и конца партии, рекордов. Описание событий: [docs/analytics.md](docs/analytics.md).

## Требования

- iOS 17.0 или новее (на iOS 18+ используется новый `TabView` с отдельной вкладкой поиска, на iOS 26 панель вкладок сворачивается при прокрутке)
- Xcode 26 или новее (проект использует API iOS 26 SDK)
- Swift 5

## Запуск

```bash
git clone https://github.com/nuralisugirbekov/PuzzleBox.git
cd PuzzleBox
open PuzzleBoxApp.xcodeproj
```

При открытии Xcode сам загрузит Firebase iOS SDK (12.x) через Swift Package Manager. Затем выберите симулятор iPhone и нажмите **Run** (Cmd+R).

Чтобы запустить на своём устройстве, откройте **Signing & Capabilities**, выберите свою команду разработчика в поле **Team** и при необходимости поменяйте Bundle ID. Для аналитики нужен свой `GoogleService-Info.plist` с совпадающим Bundle ID.

## Структура проекта

```
PuzzleBoxApp/
├── PuzzleBoxAppApp.swift       точка входа, инициализация Firebase
├── Core/
│   ├── GameCore.swift          каталог игр (GameID), категории, протокол GameEngine
│   ├── StatsStore.swift        рекорды, избранное, недавние игры
│   ├── Localization.swift      выбор языка и L10n
│   ├── AppAnalytics.swift      события Firebase Analytics
│   ├── SoundFX.swift           синтез звуков
│   ├── CardKit.swift           колода и отрисовка карт
│   ├── CardRoundClock.swift    таймер карточных партий
│   └── ChessPuzzleLibrary.swift
├── Games/
│   ├── *View.swift             классические игры (Sudoku, Solitaire, 2048 и др.)
│   ├── Arcade/                 Stack, Knife Spin, Helix Drop, Merge Fruit, Simon…
│   ├── ArrowEscape/            головоломка Arrow Escape
│   ├── ArrowMaze/              Rocket Maze (SpriteKit)
│   ├── Bounce/
│   ├── Collection/             сборники логических и реакционных мини-игр
│   ├── Expansion/              Slope, Circle Pong, Space Dodge, Endless Climb
│   └── Playground/             физика, внимание и визуальные головоломки
├── UI/
│   ├── RootTabView.swift       вкладки, настройки, запуск игр
│   ├── HomeView / DiscoverView / RatingView / GamesView / SearchView
│   ├── GameContainerView.swift общий экран игры, пауза, результаты
│   ├── GameArtwork.swift       обложки игр
│   ├── GameTutorialView.swift  экран «Как играть»
│   └── Theme.swift, GameTheme.swift
├── Resources/MateInOne.json    шахматные задачи
└── *.lproj/                    локализации
docs/                           заметки по аналитике и отдельным играм
```

Чтобы добавить игру, нужны движок, реализующий `GameEngine`, view на базе `GameContainerView`, новый case в `GameID` с `GameInfo` и строка в `gameView(for:)`.

## Лицензия

[MIT](LICENSE) — используйте свободно, сохраняя указание авторства.
