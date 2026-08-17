# Phase 2 - Sprava tras a jizd

## Cil faze

Vytvorit spolehlivou spravu tras a ulozenych jizd tak, aby bylo mozne:

- vytvaret a pojmenovavat trasy,
- ukladat jizdy bez ztraty i bez predem vybrane trasy,
- prirazovat jizdy k trasam,
- prohlizet jizdy podle trasy,
- upravovat zakladni parametry trasy,
- pripravit data pro pozdejsi realtime srovnavani ve Phase 3.

Phase 2 neresi samotne realtime porovnavani ani ranking. Jejim vysledkem je stabilni datovy a uzivatelsky zaklad pro Phase 3.

## Zakladni pravidla

### Trasy

1. Kazda uzivatelska trasa musi mit jmeno.
2. Jmeno trasy nesmi byt prazdne.
3. Jmeno musi byt jednoznacne alespon v ramci aktivnich tras, nebo aplikace musi pri duplicite zobrazit jasne upozorneni.
4. Trasa muze mit volitelny popis.
5. Trasa muze mit volitelny start, cil a tolerancni polomer. Tyto udaje budou vyuzity pozdeji pri zarovnani a porovnavani jizd.
6. Uzivatelska trasa muze existovat pouze tehdy, pokud obsahuje alespon jednu jizdu.
7. Trasa s posledni jizdou se nesmi smazat bez rozhodnuti, kam bude jizda presunuta.

### Nezarazene jizdy

1. Jizda s `route_id = NULL` je nezarazena.
2. Nezarazene jizdy nejsou trasa a nemaji vlastni zaznam v tabulce `Routes`.
3. Jizda bez vybrane trasy se po ulozeni automaticky ulozi s `route_id = NULL`.
4. Nezarazena jizda muze byt pozdeji prirazena k uzivatelske trase.
5. V Route Management se nezarazene jizdy zobrazi v samostatne sekci "Nezarazene jizdy".

## Datovy model

### Routes

Overit a pripadne rozsirit tabulku `Routes`:

- `id`
- `name` - povinne pro uzivatelske trasy
- `description` - volitelne
- `start_lat`, `start_lon` - volitelne pro nove trasy
- `end_lat`, `end_lon` - volitelne pro nove trasy
- `tolerance_radius` - volitelne, vychozi hodnota
- `created_at`
- `updated_at`
- pripadne `archived_at` nebo `is_deleted` pro bezpecne archivovani

Soucasne schema ma `start_lat`, `start_lon`, `end_lat` a `end_lon` jako `NOT NULL`. Bude nutna migrace, ktera povoli `NULL` pro start a cil, protoze tyto udaje nemusi byt pri vytvoreni trasy zname.

### Rides

Overit a upravit vazbu:

- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `route_id` - volitelne; `NULL` znamena nezarazenou jizdu
- `gpx_filename` - nazev souboru v adresari `gpx/` (pro nami vytvorene soubory: `{nick}_{YYYY-MM-DD}_{HH-MM-SS}.gpx`; importovane mohou mit jine jmeno)
- `user_nick` - nick uzivatele
- `saved_at` - ISO 8601 cas prvniho zaznameaneho GPS bodu (absolutni cas ulozeni zaznamu)
- `start_time` - ISO 8601 cas trimovaneho startu (prvni bod v uvazenem trimovani, muze se zmenit pri nastaveni start/end pozic trasy)
- `duration_seconds` - ciste trvani jizdy v sekundach (vypocitano z trimovanych bodu)
- `distance_meters` - vzdalenost vypocitana z GPX bodu
- `avg_speed_kmh` - prumernym: distance_meters / duration_seconds
- `updated_at` - cas posledni upravy (pro audit: trimovani, prerazeni trasy, atd.)

Jizda muze byt ulozena bez vazby na trasu. Pri nevybrane nebo nezname trase se pouzije `route_id = NULL`; jizda se nesmi ztratit kvuli chybejicimu kontextu.

**Trimovani jizd (dulezite pro fazi 3):**

Uzivatel se muze pripravovat na jizdu jeste pred fyzickym vyrazem: zapne zaznam, ulozi telefon, ceka, ... Podobne na konci: jizda skoncil, ale vypina zaznam az pozdeji. GPX soubor obsahuje vsechny body od prvniho zapnuti do vypnuti.

Pri nastaveni start a end pozic trasy (na mape) aplikace:
1. Parsuje vsechny body z GPX souboru
2. Najde prvni bod po start pozici (nejblizsi bodu)
3. Najde posledni bod pred end pozici
4. Prepocita `start_time` (cas tohoto bodu), `duration_seconds` a `distance_meters` podle trimovanych bodu
5. Fyzicky nemenuje GPX soubor - jen se zmeni metadata v SQLite

**Autodetekce pauz v jizde (v GPX):**

Pokud je zapnuta v Settings, aplikace automaticky detekuje dlouhe cekani behem jizdy (semafory, zeleznicni prejezdy, atd.):
- Hledaji se dvojice po sobe jdoucich bodu s:
  - Vzdalenosti < `pause_max_distance` (default 20m)
  - A casovym skokem > `pause_min_duration` (default 60 sekund)
- Takove casti se vypoustejici z vypoctu `duration_seconds`
- Vyhodne i pro zapauzovani: pokud uzivatel zapomene stiskout PAUSE, aplikace to zjisti
- Funguje i pri importu GPX z externiho zdroje

Pauzy se **detekuji automaticky** - neni treba ukladat samostatne. Vypocet je ciste z GPX bodu.

Vzorek flow:
- `saved_at: 14:30:00` - uzivatel zapnul zaznam (prvni bod v GPX)
- [10 minut cekani - jsou body v GPX]
- `start_time: 14:40:00` - uzivatel skutecne vyrazil (nastaveny start bod, nebo automaticky detekovan)
- [45 minut jizdy]
- **14:45:00 - semafor, pozice skoro stejna, ceka 1:30** ← detekuje se jako pausa
- **14:46:30 - semafor skoncil, pokracuje v jizde**
- `15:25:00` - uzivatel dorazil do cile
- [5 minut cekani]
- `15:30:00` - uzivatel vypnul zaznam (posledni bod v GPX)
- **Vysledek:** `duration_seconds = (45 - 1:30) minut ≈ 2610 sekund` (bez detektovanych pauz)

**GPX uloziste (novinka):**
- Vsechny GPX soubory se ukladaji do jedineho adresare: `gpx/`
- **Pojmenovani pro nami vytvorene soubory:** `{nick}_{YYYY-MM-DD}_{HH-MM-SS}.gpx`
  - Pri kolizi (nahoda stejneho casu): `{nick}_{YYYY-MM-DD}_{HH-MM-SS}_01.gpx`, `_02.gpx`, atd.
- **Importovane soubory:** Mohou mit jine pojmenovani, aplikace je akceptuje tak jak jsou (format pojmenovani neni dulezity pro beh aplikace, pouze pro nami vytvorene)
- **Hlavni vyhody:**
  - Jednoducha, flat struktura bez vnoreni
  - Organizace resena v SQLite metadatech, ne v adresarech
  - Flexibilnejsi - presun jizdy mezi trasami nemenive fyzickou strukturu
  - Moznost logickeho prirazeni stejneho souboru k vice trasam
  - Bezpecnejsi import - soubor existuje driv, nez metadata v DB

SQLite cizi klic s nullable `route_id` tuto variantu podporuje. Dotazy pro nezarazene jizdy musi pouzivat `WHERE route_id IS NULL`, ne `route_id = ?`.

### Settings (Aktualizace)

Doplnit tabulku `Settings` o nove pole pro konfiguraci autodetekce pauz:

- `id` (INTEGER PRIMARY KEY)
- Existujici:
  - `user_nick`
  - `gps_recording_interval_seconds`
  - `min_distance_for_gps_point`
  - `num_rides_to_compare`
- **Nove (pro autodetekci pauz):**
  - `pause_detection_enabled` (BOOLEAN, default: 1/true)
  - `pause_max_distance_meters` (INTEGER, default: 20) - maximalni vzdalenost mezi body, aby se pocitaly jako "stejne miste"
  - `pause_min_duration_seconds` (INTEGER, default: 60) - minimalni cas skoku mezi body, aby se pocital jako pausa

Tyto konstanty uzivateli umozni:
- Vypnout autodetekci, pokud ji nechce (pause_detection_enabled = 0)
- Upravit citlivost detekce podle svych potreby (napr. delsi minimalni cekani pro semafory v meste)

### Migrace existujicich dat

1. Vytvorit novou verzi tabulky `Rides` s nullable `route_id`, protoze SQLite bezne neumoznuje odstranit `NOT NULL` z existujiciho sloupce primym `ALTER TABLE`.
2. Prekopirovat existujici jizdy do nove tabulky a zachovat jejich ID, metadata a GPX cesty.
3. Existujici jizdy s `route_id = 0` prevest na `route_id = NULL`, pokud jde o dosavadni nezarazene jizdy.
4. Zachovat existujici GPX soubory a cesty.
5. Doplnit databazovou verzi a migracni test.
6. Overit, ze migrace je opakovatelna a nesmaze zadnou jizdu.

## Uzivatelske workflow

### Seznam tras

Route Management zobrazi:

- seznam uzivatelskych tras,
- pocet jizd v kazde trase,
- datum posledni jizdy,
- celkovou vzdalenost nebo zakladni souhrn,
	- polozku "Nezarazene jizdy" pro jizdy s `route_id IS NULL`, pouze pokud existuji,
- akci pro vytvoreni nove trasy.

Prazdne uzivatelske trasy se nevytvareji. Trasa vznika az s prvni jizdou, nebo se prazdna rozpracovana trasa musi pred opustenim obrazovky zrusit.

### Vytvoreni trasy

1. Uzivatel zvoli vytvoreni trasy.
2. Zada povinne jmeno.
3. Volitelne zada popis, start, cil a tolerancni polomer.
4. Aplikace validuje jmeno.
5. Trasa se ulozi az ve chvili, kdy k ni bude prirazena prvni jizda.
6. Po vytvoreni se trasa stane vybranou trasou pro dalsi zaznam.

### Vyber trasy pro novou jizdu

1. Uzivatel ve sprave tras vybere trasu.
2. Vybrana trasa se ulozi jako aktualni kontext pro Live Map.
3. START vytvori novou jizdu s touto trasou.
4. Pokud neni vybrana zadna uzivatelska trasa, jizda se ulozi jako nezarazena (`route_id = NULL`).
5. Po restartu aplikace se vybrana trasa obnovi, nebo se pouziji nezarazene jizdy.

### Ulozeni jizdy

1. START zahaji zaznam v aktualne vybrane trase.
2. PAUSE a RESUME zachovaji prirazeni ke stejne trase.
3. STOP dokonci zaznam, spocita statistiky a ulozi metadata.
4. **GPX soubor se ulozi do adresare `gpx/` s nazvem `{nick}_{YYYY-MM-DD}_{HH-MM-SS}.gpx`**
   - Pri kolizi (nahodna duplikace stejneho casu): `{nick}_{YYYY-MM-DD}_{HH-MM-SS}_01.gpx`
   - `gpx_filename` (bez cesty) se ulozi do SQLite
5. **Inicialnim trimovanim (bez nastaveni trasy):**
   - `saved_at` = cas prvniho zaznameaneho bodu (z GPX)
   - `start_time` = `saved_at` (zatim nema trimovani)
   - `duration_seconds` se vypocita z prvniho a posledniho bodu v GPX
   - `distance_meters` se vypocita z vsech bodu
6. Pri chybe ulozeni se uzivateli zobrazi chyba a jizda zustane v pameti nebo v obnovitelnem stavu.
7. Pokud je kontext trasy neznamy, ulozi se jizda jako nezarazena (`route_id = NULL`).

### Sprava jizdy

U kazde jizdy musi byt mozne:

- zobrazit detail,
- zobrazit trasu na mape,
- zobrazit datum, cas, vzdalenost a prumernou rychlost,
- zmenit prirazeni k jine trase,
- prejmenovat pouze trasu, ne historicka data jizdy,
- exportovat nebo otevrit GPX,
- smazat jizdu s potvrzenim.

### Presun jizdy

1. Uzivatel zvoli jizdu a akci "Priradit k trase".
2. Vybere existujici trasu, nebo vytvori novou.
3. Aplikace zkontroluje, ze cilova trasa ma jmeno.
4. Aktualizuje se pouze `route_id` v SQLite; **GPX soubor v adresari `gpx/` se nemenuje** - stejny soubor muze byt logicky prirazen vic trasam
5. **Prepocita se trimovani podle start/end pozic nove trasy:**
   - Pokud je nova trasa ma nastavene start a end pozice, aplikace parsuje GPX
   - Najde prvni bod po start pozici a posledni bod pred end pozici
   - Prepocita: `start_time`, `duration_seconds`, `distance_meters`
   - Aktualizuje se `updated_at`
6. Pokud puvodni uzivatelska trasa po presunu nema zadnou jizdu, nabidne se jeji archivace nebo smazani.
7. Jizda nikdy nesmi zmizet kvuli tomu, ze se stala nezaazenou.

## UI obrazovky

### Route Management screen

Implementovat postupne:

1. prazdny stav bez tras,
2. seznam tras a pocty jizd,
3. detail trasy se seznamem jizd,
4. formular vytvoreni a editace trasy,
5. detail jizdy,
6. akce pro presun, export a smazani jizdy,
7. potvrzovaci dialogy pro mazani.

### Live Map napojeni

Doplnit:

- zobrazeni aktualne vybrane trasy,
- vyber trasy pred START,
- jasnou informaci, kdy se jizda uklada do "Nezarazene jizdy",
- zabraneni zmene trasy uprostred aktivniho zaznamu,
- bezpecne chovani pri navratu na Live Map.

## Servisni vrstvy

Doporucene odpovednosti:

- `DatabaseService` - migrace, CRUD tras a jizd, agregace poctu jizd vcetne nezarazenych
- `RouteService` - vyber trasy, validace a presuny jizd mezi `NULL` a konkretni trasou
- `RideService` - zaznam jizdy a ulozeni do prave aktualni trasy
- `GpxService` - generovani, cteni a umisteni GPX souboru
- **`GpxProcessingService`** (nova) - parsing GPX bodu, trimovani podle start/end pozic, **autodetekce pauz** z GPS dat
- `RouteManagementScreen` - seznamy, formulare a akce

Prednost ma existujici service/singleton styl projektu. Novy `RouteService` pridat pouze pokud zjednodusi pravidla vyberu a presunu jizd. `GpxProcessingService` je dulezita pro spravne vypocty `duration_seconds` a vzdalenosti.

## Poradi implementace

1. Ujasnit a migrovat databazove schema tras a jizd na nullable `route_id` (bez `end_time`, s `duration_seconds`, `saved_at`, `start_time`).
2. Doplnit Settings o nove pole pro autodetekci pauz: `pause_detection_enabled`, `pause_max_distance_meters`, `pause_min_duration_seconds`.
3. Implementovat bezpecne ukladani a zobrazovani neza razenych jizd.
4. Doplnit CRUD operace pro trasy.
5. Doplnit CRUD operace a agregace pro jizdy.
6. **Implementovat GpxProcessingService:**
   - Parsing GPX bodu z souboru
   - Trimovani podle start/end pozic
   - **Autodetekce pauz:** najiti dvojic bodu s vzdalenosti < pause_max_distance a casovym skokem > pause_min_duration
   - Vypocet ciste duration_seconds a distance_meters (bez pauz)
7. Pridat persistentni aktualne vybranou trasu.
8. Implementovat seznam tras.
9. Implementovat detail trasy a seznam jizd.
10. Implementovat vytvoreni a editaci trasy, vcetne nastaveni start a end pozic (s prepocitanim trimovani jizd).
11. Implementovat presun, export a mazani jizd (s aktualizaci trimovani pri zmene trasy).
12. Napojit vyber trasy na START/STOP.
13. Doplnit migracni, servisni a widget testy.
14. Aktualizovat README a APP_REQUIREMENTS po dokonceni faze.

## Akceptacni kriteria

- Jizda bez vybrane trasy se ulozi s `route_id = NULL`.
- Nezarazene jizdy se zobrazi oddelene od uzivatelskych tras.
- Kazda uzivatelska trasa ma neprazdne jmeno.
- Kazda zobrazena uzivatelska trasa obsahuje alespon jednu jizdu.
- Uzivatel vidi pocet jizd u trasy.
- Uzivatel muze otevrit detail trasy a zobrazit jeji jizdy.
- Uzivatel muze priradit jizdu k jine trase bez ztraty GPX souboru.
- Uzivatel muze smazat jizdu s potvrzenim.
- Aktivni zaznam nelze omylem prepnout do jine trasy.
- **Trimovani jizd:**
  - Pri ulozeni jizdy se automaticky naplni `saved_at` (prvni bod) a `start_time = saved_at`
  - Pri nastaveni start a end pozic trasy se prepocita trimovani: `start_time`, `duration_seconds`, `distance_meters`
  - Pri presunu jizdy do jine trasy se prepocita trimovani podle start/end pozic nove trasy
  - GPX soubor se nemeni - jen metadata v SQLite
- **Autodetekce pauz:**
  - Pokud je `pause_detection_enabled` zapnuta v Settings, aplikace detekuje dlouhe cekani z GPX dat
  - Detekuje se: vzdalenost < `pause_max_distance_meters` (default 20m) AND cas skok > `pause_min_duration_seconds` (default 60s)
  - Detektovane pauzy se vypoustejici z vypoctu `duration_seconds` a `distance_meters`
  - Uzivatel muze autodetekci vypnout nebo upravit citlivost v Settings
  - Funguje i pro importovane GPX soubory
- Existujici data projdou migraci bez ztraty.
- Data Phase 2 jsou pripravena pro vyber trasy a porovnavani ve Phase 3.

## Mimo rozsah Phase 2

- realtime ranking a virtualni zavodnici,
- vypocet casove ztraty oproti jine jizde,
- Course-Up orientace mapy,
- plne offline mapove podklady,
- automaticke rozpoznavani stejne trasy podle GPS koridoru.

## Otevrene rozhodnuti pred implementaci

- Zda se uzivatelska trasa vytvori pred prvni jizdou, nebo az pri prvnim ulozeni jizdy.
- Zda se pri smazani posledni jizdy trasa automaticky archivuje, nebo se uzivateli nabidne potvrzene smazani.
- **Zda se detektovane pauzy zobrazi uzivateli v detailu jizdy** (napr. jako seznam "detektovanych zastaveni") pro ověřování korektnosti detekce.
