import Foundation

/// The word languages Hangman supports. The app's language picks one; the
/// languages without a letter alphabet suited to guessing letter by letter
/// (Hindi, Chinese, Korean) fall back to English.
enum HangmanLanguage: String, Codable, CaseIterable {
    case english = "en"
    case russian = "ru"
    case kazakh = "kk"
    case german = "de"
    case french = "fr"

    init(app: AppLanguage) {
        switch app {
        case .russian: self = .russian
        case .kazakh: self = .kazakh
        case .german: self = .german
        case .french: self = .french
        case .english, .hindi, .chinese, .korean: self = .english
        }
    }

    /// Keyboard letters, in alphabetical order.
    var alphabet: [String] {
        switch self {
        case .english, .french:
            return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        case .german:
            return "ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ".map(String.init)
        case .russian:
            // Ё is folded into Е, as is usual in word games.
            return "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ".map(String.init)
        case .kazakh:
            return "АӘБВГҒДЕЁЖЗИЙКҚЛМНҢОӨПРСТУҰҮФХҺЦЧШЩЪЫІЬЭЮЯ".map(String.init)
        }
    }

    /// Upper-case words of 4–10 letters, every letter on the keyboard.
    var words: [String] {
        switch self {
        case .english: Self.englishWords
        case .russian: Self.russianWords
        case .kazakh: Self.kazakhWords
        case .german: Self.germanWords
        case .french: Self.frenchWords
        }
    }

    /// Letters by how many dictionary words contain them, most common first.
    /// The bot falls back on this order when it isn't reasoning about the word.
    var letterFrequency: [String] { Self.frequencies[self] ?? alphabet }

    private static let frequencies: [HangmanLanguage: [String]] = Dictionary(
        uniqueKeysWithValues: allCases.map { language in
            var counts: [String: Int] = [:]
            for word in language.words {
                for letter in Set(word.map(String.init)) { counts[letter, default: 0] += 1 }
            }
            return (language, language.alphabet.sorted { counts[$0, default: 0] > counts[$1, default: 0] })
        })

    // MARK: Word lists

    private static let englishWords = """
    APPLE BANANA ORANGE CHERRY GRAPE LEMON MANGO PEACH PEAR MELON \
    TIGER LION ZEBRA MONKEY RABBIT HORSE DONKEY TURTLE PARROT PENGUIN \
    DOLPHIN WHALE SHARK OCTOPUS SPIDER BUTTERFLY EAGLE FALCON SQUIRREL GIRAFFE \
    HOUSE GARDEN WINDOW KITCHEN BEDROOM PILLOW BLANKET MIRROR CANDLE LADDER \
    BRIDGE CASTLE TOWER VILLAGE CITY STREET MARKET SCHOOL LIBRARY MUSEUM \
    ISLAND FOREST DESERT RIVER OCEAN MOUNTAIN VALLEY VOLCANO JUNGLE MEADOW \
    WINTER SUMMER AUTUMN SPRING THUNDER RAINBOW CLOUD SNOWMAN WEATHER STORM \
    PLANET ROCKET COMET GALAXY STAR MOON SUNSHINE ASTRONAUT \
    GUITAR PIANO VIOLIN TRUMPET DRUMS MUSIC SINGER DANCER CONCERT \
    DOCTOR TEACHER FARMER PILOT SAILOR BAKER PAINTER WRITER ARTIST DRIVER \
    BICYCLE TRAIN AIRPLANE TRUCK SUBMARINE HELICOPTER TICKET JOURNEY \
    PENCIL ERASER NOTEBOOK BACKPACK LETTER STAMP PUZZLE RIDDLE TREASURE \
    COFFEE CHEESE BUTTER BREAD COOKIE CHOCOLATE PANCAKE SANDWICH NOODLE \
    PIZZA BURGER SALAD TOMATO POTATO CARROT ONION PEPPER GARLIC \
    JACKET SWEATER BOOTS SCARF GLOVES POCKET BUTTON UMBRELLA WALLET \
    FOOTBALL TENNIS HOCKEY SOCCER CHESS GOALKEEPER MEDAL TROPHY \
    KEYBOARD MONITOR CAMERA PHONE BATTERY ROBOT MAGNET COMPASS LANTERN \
    DRAGON WIZARD KNIGHT PIRATE PRINCESS GIANT MONSTER GHOST UNICORN \
    FRIEND FAMILY HOLIDAY BIRTHDAY PRESENT BALLOON PARTY SECRET WHISPER
    """.split(separator: " ").map(String.init)

    private static let russianWords = """
    ЯБЛОКО БАНАН АПЕЛЬСИН ВИШНЯ ВИНОГРАД ЛИМОН ГРУША АРБУЗ ДЫНЯ МАЛИНА \
    КЛУБНИКА ПЕРСИК АБРИКОС СЛИВА ТИГР ЗЕБРА ОБЕЗЬЯНА КРОЛИК ЛОШАДЬ ЧЕРЕПАХА \
    ПОПУГАЙ ПИНГВИН ДЕЛЬФИН АКУЛА ОСЬМИНОГ ПАУК БАБОЧКА ОРЕЛ БЕЛКА ЖИРАФ \
    МЕДВЕДЬ ВОЛК ЛИСИЦА ЗАЯЦ СОБАКА КОШКА КОРОВА ВЕРБЛЮД СЛОН КЕНГУРУ \
    КВАРТИРА КУХНЯ СПАЛЬНЯ ПОДУШКА ОДЕЯЛО ЗЕРКАЛО СВЕЧА ЛЕСТНИЦА ОКНО ДИВАН \
    МОСТ ЗАМОК БАШНЯ ДЕРЕВНЯ ГОРОД УЛИЦА РЫНОК ШКОЛА БИБЛИОТЕКА МУЗЕЙ \
    ОСТРОВ ПУСТЫНЯ РЕКА ОКЕАН ГОРА ДОЛИНА ВУЛКАН ДЖУНГЛИ ПОЛЯНА БОЛОТО \
    ЗИМА ЛЕТО ОСЕНЬ ВЕСНА ГРОЗА РАДУГА ОБЛАКО СНЕГОВИК ПОГОДА МЕТЕЛЬ \
    ПЛАНЕТА РАКЕТА КОМЕТА ГАЛАКТИКА ЗВЕЗДА КОСМОНАВТ СПУТНИК ТЕЛЕСКОП \
    ГИТАРА ПИАНИНО СКРИПКА ТРУБА БАРАБАН МУЗЫКА ПЕВЕЦ ТАНЕЦ КОНЦЕРТ ПЕСНЯ \
    ВРАЧ УЧИТЕЛЬ ФЕРМЕР ПИЛОТ МОРЯК ПЕКАРЬ ХУДОЖНИК ПИСАТЕЛЬ ВОДИТЕЛЬ ПОВАР \
    ВЕЛОСИПЕД ПОЕЗД САМОЛЕТ ГРУЗОВИК ВЕРТОЛЕТ ТРАМВАЙ АВТОБУС БИЛЕТ ДОРОГА \
    КАРАНДАШ ЛАСТИК ТЕТРАДЬ РЮКЗАК ПИСЬМО МАРКА ЗАГАДКА СОКРОВИЩЕ КНИГА \
    СМЕТАНА МАСЛО ХЛЕБ ПЕЧЕНЬЕ ШОКОЛАД БЛИНЫ БУТЕРБРОД ПИЦЦА САЛАТ ПОМИДОР \
    КАРТОФЕЛЬ МОРКОВЬ ЛУКОВИЦА ЧЕСНОК КАПУСТА ОГУРЕЦ КАША ПЕЛЬМЕНИ КОМПОТ ВАРЕНЬЕ \
    КУРТКА СВИТЕР САПОГИ ШАРФ ПЕРЧАТКИ КАРМАН ПУГОВИЦА ЗОНТИК КОШЕЛЕК ШАПКА \
    ФУТБОЛ ТЕННИС ХОККЕЙ ШАХМАТЫ ВРАТАРЬ МЕДАЛЬ КУБОК СТАДИОН ЛЫЖИ КОНЬКИ \
    КЛАВИАТУРА КАМЕРА ТЕЛЕФОН БАТАРЕЙКА РОБОТ МАГНИТ КОМПАС ФОНАРЬ ЧАСЫ \
    ДРАКОН ВОЛШЕБНИК РЫЦАРЬ ПИРАТ ПРИНЦЕССА ВЕЛИКАН ЧУДОВИЩЕ ПРИВИДЕНИЕ \
    ДРУГ СЕМЬЯ ПРАЗДНИК ПОДАРОК ШАРИК СЕКРЕТ ШЕПОТ УЛЫБКА СКАЗКА ИГРУШКА
    """.split(separator: " ").map(String.init)

    private static let kazakhWords = """
    КІТАП МЕКТЕП ҚАЛАМ ДӘПТЕР ҮСТЕЛ ОРЫНДЫҚ ТЕРЕЗЕ ЕСІК АСПАН ЖҰЛДЫЗ \
    ӨЗЕН ТЕҢІЗ ОРМАН АҒАШ ЖАПЫРАҚ ЖЕМІС АЛМА ҚАРБЫЗ ҚАУЫН ЖҮЗІМ \
    ІРІМШІК ТАМАҚ ҚАНТ БАЛЫҚ ЖЫЛҚЫ ТҮЙЕ СИЫР ЕШКІ МЫСЫҚ ҚОЯН \
    ҚАСҚЫР ТҮЛКІ АРЫСТАН БҮРКІТ ТОРҒАЙ КӨБЕЛЕК ҚҰМЫРСҚА ДОМБЫРА ҚАЛА АУЫЛ \
    КӨШЕ КӨПІР МАШИНА ПОЙЫЗ ҰШАҚ КЕМЕ ВЕЛОСИПЕД ОЙЫНШЫҚ ОТБАСЫ БАЛА \
    ДӘРІГЕР МҰҒАЛІМ ОҚУШЫ ЖҰМЫС САҒАТ ТЕЛЕФОН ҚАРЫНДАШ СУРЕТ КИНО ТЕАТР \
    МУЗЫКА КӨКТЕМ ЖАҢБЫР БҰЛТ БАҚША ДАЛА ЕЛОРДА ӘРІП КІТАПХАНА ДҮКЕН \
    БАЗАР АУРУХАНА ПОШТА СЫЙЛЫҚ МЕРЕКЕ БАЛМҰЗДАҚ ТОРТ БАУЫРСАҚ ҚЫМЫЗ КҮРІШ \
    КАРТОП ПИЯЗ САБІЗ ҚИЯР ҚЫЗАНАҚ АЛМҰРТ ӨРІК ЖАҢҒАҚ КӨЙЛЕК ШАЛБАР \
    ЕТІК ҚАЛПАҚ БӨРІК ҚОЛҒАП САЯБАҚ СТАДИОН ШАХМАТ АСЫҚ ЖҮРЕК ҚҰЛАҚ \
    МҰРЫН АУЫЗ ҚАСЫҚ ШАНЫШҚЫ ПЫШАҚ КЕСЕ ТАБАҚ ШӘЙНЕК БӨЛМЕ ТӨСЕК \
    КІЛЕМ АЙНА ШЫРАҚ ЖАРЫҚ ДОСТЫҚ ЕРТЕГІ ҚҰПИЯ ҚАЗЫНА БАТЫР ПАТША
    """.split(separator: " ").map(String.init)

    private static let germanWords = """
    APFEL BANANE ORANGE KIRSCHE TRAUBE ZITRONE BIRNE MELONE ERDBEERE PFIRSICH \
    TIGER ZEBRA AFFE HASE PFERD ESEL KRÖTE PAPAGEI PINGUIN DELFIN \
    KRAKE SPINNE ADLER FALKE GIRAFFE WOLF FUCHS \
    HAUS GARTEN FENSTER KÜCHE KISSEN DECKE SPIEGEL KERZE LEITER SOFA \
    BRÜCKE BURG TURM DORF STADT MARKT SCHULE MUSEUM INSEL WALD \
    WÜSTE FLUSS OZEAN BERG VULKAN DSCHUNGEL WIESE WINTER SOMMER HERBST \
    FRÜHLING GEWITTER REGENBOGEN WOLKE WETTER STURM PLANET RAKETE KOMET STERN \
    MOND GITARRE KLAVIER GEIGE TROMPETE TROMMEL MUSIK SÄNGER TÄNZER KONZERT \
    ARZT LEHRER BAUER PILOT BÄCKER MALER KÜNSTLER FAHRER KOCH \
    FAHRRAD FLUGZEUG LASTWAGEN FAHRKARTE REISE \
    BLEISTIFT HEFT RUCKSACK BRIEF RÄTSEL SCHATZ BUCH KAFFEE KÄSE BUTTER \
    BROT KEKS SCHOKOLADE NUDEL PIZZA SALAT TOMATE KARTOFFEL KAROTTE \
    ZWIEBEL PAPRIKA JACKE PULLOVER STIEFEL SCHAL HANDSCHUH KNOPF  \
    FUSSBALL TENNIS SCHACH TORWART MEDAILLE POKAL KAMERA TELEFON ROBOTER MAGNET \
    KOMPASS LATERNE DRACHE ZAUBERER RITTER PIRAT PRINZESSIN RIESE GESPENST EINHORN \
    FREUND FAMILIE URLAUB GEBURTSTAG GESCHENK BALLON GEHEIMNIS MÄRCHEN SPIELZEUG
    """.split(separator: " ").map(String.init)

    private static let frenchWords = """
    POMME BANANE ORANGE CERISE RAISIN CITRON POIRE MELON FRAISE PECHE \
    TIGRE ZEBRE SINGE LAPIN CHEVAL TORTUE PERROQUET PINGOUIN DAUPHIN BALEINE \
    REQUIN PIEUVRE ARAIGNEE PAPILLON AIGLE FAUCON ECUREUIL GIRAFE OURS RENARD \
    MAISON JARDIN FENETRE CUISINE OREILLER MIROIR BOUGIE ECHELLE CANAPE \
    CHATEAU VILLAGE VILLE MARCHE ECOLE MUSEE FORET DESERT RIVIERE \
    OCEAN MONTAGNE VALLEE VOLCAN JUNGLE PRAIRIE HIVER AUTOMNE PRINTEMPS ORAGE \
    NUAGE TEMPETE PLANETE FUSEE COMETE GALAXIE ETOILE LUNE SOLEIL \
    GUITARE PIANO VIOLON TROMPETTE TAMBOUR MUSIQUE CHANTEUR DANSEUR CONCERT \
    MEDECIN FERMIER PILOTE MARIN BOULANGER PEINTRE ECRIVAIN ARTISTE CHAUFFEUR \
    VELO TRAIN AVION CAMION BATEAU BILLET VOYAGE \
    CRAYON GOMME CAHIER CARTABLE LETTRE TIMBRE ENIGME TRESOR LIVRE \
    FROMAGE BEURRE BAGUETTE BISCUIT CHOCOLAT CREPE SANDWICH PIZZA SALADE TOMATE \
    CAROTTE OIGNON POIVRON VESTE PULL BOTTES ECHARPE GANTS POCHE \
    BOUTON PARAPLUIE FOOTBALL TENNIS ECHECS MEDAILLE TROPHEE CLAVIER CAMERA \
    TELEPHONE ROBOT AIMANT BOUSSOLE LANTERNE DRAGON SORCIER CHEVALIER PIRATE \
    PRINCESSE GEANT MONSTRE FANTOME LICORNE FAMILLE VACANCES CADEAU BALLON SECRET
    """.split(separator: " ").map(String.init)
}
