# Chess puzzle bank

iOS now offers a pre-round duration selector: 30, 60, or 120 seconds (default 60). The board is hidden until Start; restart returns to duration selection. At expiry the round finishes with solved count and score. The countdown includes correct/incorrect move display delays, but excludes explicit pauses and background time. Android remains unchanged by this update.

Source: the user-supplied `23.pdf`, László Polgár's *5334 Problems, Combinations & Games*, chapter 1.1 (Mate in 1). Imported on 2026-10-01.

`PuzzleBoxApp/Resources/MateInOne.json` now contains all 306 diagrams numbered 1–306 from physical PDF pages 16–66, replacing the previous 500-record JSON. Later chapters contain longer problems and are not used in the 30-second mate-in-one challenge. Page 67 has only the number 307, without a board; solution 307 belongs to the mate-in-two section.

Each record stores `source_id`, `source_page`, `fen`, the book's preferred UCI move in `best`, and every legal mating UCI move in `solutions`. The chess font has two glyphs for each piece, depending on square color. Both map to the same piece; capitalization determines its side. White moves in all imported positions.

All 306 positions passed python-chess position validation. Every legal move was enumerated, and every printed primary solution and parenthesized alternative on physical pages 972–977 was checked to deliver checkmate. Five positions (71, 122, 154, 220, 261) have two mating moves; all others have one. Task 243 prints `c4+`, but the verified move is actually checkmate. No piece placements needed correction.

Two diagrams need history-dependent FEN fields established by the printed solutions: task 305 allows White's kingside castling (`K`), and task 306 allows en passant on `b6`. Other positions use no castling or en passant rights. Diagram pages were also sampled visually to confirm the piece mapping and special positions.

Reproduce extraction and chess validation with Python plus `pypdf` and `python-chess`:

```sh
python3 scripts/import_pdf_mates.py /path/to/23.pdf PuzzleBoxApp/Resources/MateInOne.json
```

The importer fails before replacing the output if a diagram, task number, position, or printed solution is invalid. It is specific to this PDF's page layout and encoding.

Each new iOS game starts a challenge of the selected duration with a shuffled bank, excluding duplicate board layouts. Every solved puzzle awards 100 points; errors do not subtract points. After a correct move, the final position and a localized checkmate message remain visible for 1.5 seconds. Further moves are blocked during this interval, and the next puzzle loads automatically. On iOS this interval is included in the challenge countdown. The timer uses monotonic elapsed time and stops on pause, while the scene is inactive, and after leaving the screen. Expiry blocks moves and shows the solved count and score. Restart resets the score, solved count, and time. The data is bundled for offline play; the small built-in set remains a loading fallback, restricted to mate-in-one puzzles in this mode.

The engine accepts any stored mating move. Promotions are automatic; if more than one promotion mates on the same destination, the book's preferred promotion takes priority. Move hints reject moves exposing White's king, including special handling for en passant and castling. Only white pieces can be selected. The app was not built or run, and app tests were not run, per the user's request; validation above concerns the imported chess data.
