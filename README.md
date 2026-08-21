# PuzzleBox

Коллекция из 12 головоломок и карточных игр для iPhone и iPad. Написана на SwiftUI, без внешних зависимостей.

## Игры

| Игра | Категория | Сложность |
|---|---|---|
| Three in a Row | Casual | Easy |
| Block Blast | Logic | Easy |
| Dominoes | Cards | Easy |
| Mini Sudoku | Logic | Medium |
| Snake | Arcade | Medium |
| Water Sort | Logic | Medium |
| Minesweeper | Logic | Medium |
| Solitaire | Cards | Medium |
| Spades | Cards | Medium |
| Spider | Cards | Hard |
| FreeCell | Cards | Hard |
| Checkmate | Logic | Hard |

## Возможности

- Главное меню с поиском и фильтрами по категориям
- Кнопка **Random Game** — случайная игра одним нажатием
- Счётчик сыгранных партий, статистика хранится локально в `UserDefaults`
- Тёмная тема, тактильная отдача, единый визуальный стиль

## Требования

- iOS 17.0 или новее
- Xcode 15 или новее
- Swift 5

## Запуск

```bash
git clone https://github.com/nuralisugirbekov/PuzzleBox.git
cd PuzzleBox
open PuzzleBoxApp.xcodeproj
```

Дальше в Xcode выберите симулятор и нажмите **Run** (Cmd+R).

Чтобы запустить на своём устройстве, откройте **Signing & Capabilities** и выберите свою команду разработчика в поле **Team** — в репозитории оно намеренно пустое.

## Структура проекта

```
PuzzleBoxApp/
├── PuzzleBoxAppApp.swift   точка входа
├── Core/
│   ├── GameCore.swift      каталог игр, категории, состояния
│   ├── CardKit.swift       колода и логика карт
│   └── StatsStore.swift    статистика игрока
├── Games/                  по одному файлу на игру
└── UI/
    ├── MainMenuView.swift  меню, поиск, фильтры
    ├── GameContainerView.swift
    └── Theme.swift         цвета и стили
```

## Лицензия

[MIT](LICENSE) — используйте свободно, сохраняя указание авторства.
