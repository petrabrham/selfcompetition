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

## Jazyk uzivatelskeho rozhrani

- Vsechny texty zobrazovane uzivateli budou v anglictine, vcetne nazvu obrazovek, tlacitek, popisku, dialogu, validacnich a chybovych hlaseni, tooltipu a prazdnych stavu.
- Aktualni verze aplikace bude mit pouze anglicky jazyk.
- Budouci dalsi jazyky se budou resit standardni Flutter lokalizaci; nyni se lokalizacni vrstva neimplementuje.

## Import GPX jizd

1. Uzivatel muze do aplikace hromadne importovat existujici GPX soubory (napr. pro testovani nebo prevod historickych dat), bez nutnosti fyzicky jezdit s aplikaci.
2. V Route Management uzivatel spusti akci "Import GPX" a vybere jeden nebo vice `.gpx` souboru pres systemovy vyber souboru.
3. Pro kazdy vybrany `.gpx` soubor aplikace:
   - naparsuje GPS body,
   - spocita `distance_meters` (soucet Haversine vzdalenosti mezi body), `start_time`/`end_time` (prvni/posledni bod) a `avg_speed_kmh`,
   - presune soubor do `gpx/` (kolize reseny stejne jako u zaznamu jizdy, pripona `_01`, `_02`, ...),
   - vlozi novy zaznam do `Rides` jako nezarazenou jizdu (`route_id = NULL`), s `user_nick` z aktualnich `Settings`.
4. Soubory bez pouzitelnych GPS bodu se neimportuji; uzivatel je informovan souhrnnou hlaskou (pocet importovanych, pocet selhanych).
5. Import nijak nemeni uz importovane/ulozene jizdy; vybrany soubor se zkopiruje do interniho `gpx/` adresare.
6. Importovane jizdy lze nasledne stejne jako ostatni nezarazene jizdy presunout k trase, prejmenovat kontext nebo smazat.
7. Import je urcen predevsim pro testovani a rychle naplneni databaze daty; nenahrazuje Phase 4 pozadavek na import/export sdilenych GPX souboru (napr. z jinych aplikaci) - ten muze na tomto zakladu stavet.

## Aktivni trasa

1. Aktivni trasa je globalni, perzistentni stav ulozeny v `Settings.active_route_id` (nullable).
2. Nejvyse jedna trasa muze byt aktivni soucasne; vychozi stav (napr. prvni spusteni) je zadna aktivni trasa.
3. Aktivaci a deaktivaci trasy provadi uzivatel vyhradne v Route Management (napr. checkbox nebo prepinac u polozky trasy).
4. Aktivaci jine trasy se predchozi aktivni trasa automaticky deaktivuje (nikdy nejsou aktivni dve trasy soucasne).
5. Aktivni trasa je v seznamu vizualne odlisena (zvyrazneni nebo oznaceny stav).
6. Live Map nema tlacitko pro vyber trasy - pouze zobrazuje jmeno aktivni trasy (nebo informaci, ze zadna neni aktivni).
7. Nova jizda se automaticky priradi k aktivni trase; pokud zadna trasa neni aktivni, jizda se ulozi jako nezarazena (`route_id = NULL`).
8. Smazani aktivni trasy nastavi `active_route_id` zpet na `NULL`.
9. Aktivni trasa se obnovuje po restartu aplikace ze `Settings`.

### Vykresleni nejlepsi jizdy na Live Map

1. Pokud je trasa aktivni a ma alespon jednu jizdu, aplikace najde jizdu s nejnizsim `duration_seconds` ("nejlepsi cas").
2. GPX teto jizdy se naparsuje a vykresli na mape modrou carou.
3. Pokud ma aktivni trasa nastaveny start a/nebo cil (`start_lat/lon`, `end_lat/lon` nejsou `NULL`), zobrazi se prislusne markery.
4. Pokud zadna trasa neni aktivni, nebo aktivni trasa nema zadnou jizdu, mapa nezobrazuje zadnou stopu ani markery.

### Ride Statistics (staticka tabulka)

1. Obrazovka zobrazuje tabulku jizd aktivni trasy, serazenou vzestupne podle `duration_seconds` (nejrychlejsi nahore).
2. Sloupce: datum a cas jizdy, vzdalenost (km, 1 desetinne misto), cas jizdy (HH:mm), prumerna rychlost (km/h), casova ztrata oproti nejlepsimu casu.
3. Jizda s nejlepsim casem ma ztratu 0.
4. Pokud zadna trasa neni aktivni, obrazovka zobrazi prazdny stav s vyzvou "Vyberte aktivni trasu ve Sprave tras".
5. Zivy ranking, virtualni zavodnici a realtime porovnavani zustavaji mimo rozsah Phase 2 (viz Phase 3).

## Zakladni pravidla

### Trasy

1. Kazda uzivatelska trasa musi mit jmeno.
2. Jmeno trasy nesmi byt prazdne.
3. Jmeno musi byt jednoznacne alespon v ramci aktivnich tras, nebo aplikace musi pri duplicite zobrazit jasne upozorneni.
4. Trasa muze mit volitelny popis.
5. Trasa muze mit volitelny start, cil a tolerancni polomer. Tyto udaje budou vyuzity pozdeji pri zarovnani a porovnavani jizd.
6. Uzivatelska trasa muze existovat pouze tehdy, pokud obsahuje alespon jednu jizdu.
7. Trasa s posledni jizdou se nesmi smazat bez rozhodnuti, kam bude jizda presunuta.
8. Trasa ma `main_ride_id INTEGER NULL`, nullable referenci na `Rides.id`, ktera urcuje hlavni jizdu definujici jeji referencni geometrii.
9. Pri vytvoreni trasy je `main_ride_id = NULL`; prvni uspesne prirazena jizda se stane hlavni.
10. Uzivatel muze hlavni jizdu zmenit kontextovou akci "Set as main ride for route".
11. Hlavni jizda je oddelena od nejrychlejsi jizdy: nejrychlejsi jizda je vybrana nejmensim `duration_seconds` pro modrou referencni caru, zatimco hlavni jizda urcuje referencni geometrii a implicitni hranice trasy.

### Kontrola pred prirazenim jizdy

1. Pokud je definovan start, GPX jizdy musi obsahovat bod v tolerancnim kruhu startu.
2. Pokud je definovan cil, GPX jizdy musi obsahovat bod v tolerancnim kruhu cile.
3. Pokud start nebo cil nejsou explicitne definovany, pouzije se pro dane hranice prvni, respektive posledni GPX bod hlavni jizdy jako implicitni reference.
4. Pri `main_ride_id = NULL` neexistuje implicitni hranice; prvni uspesne prirazena jizda muze trasu inicializovat a stane se hlavni.
5. Kontrola probiha pred prirazenim pri ukonceni zaznamu, importu, prerazeni jizdy i pri zmene hlavni jizdy.
6. Pokud kontrola selze, jizda se nepriradi a zustane nezarazena (`route_id = NULL`); pri neuspesne zmene hlavni jizdy se puvodni hlavni jizda nemeni.

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
- `main_ride_id INTEGER NULL` - nullable reference na `Rides.id`, ktera definuje referencni geometrii a implicitni hranice trasy
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

`main_ride_id` je jedina autoritativni vazba pro urceni hlavni jizdy trasy. Nejlepsi jizda podle `duration_seconds` muze byt jina nez hlavni jizda. Hlavni jizda slouzi pro referencni geometrii a implicitni prvni/posledni bod trasy.

Pri smazani nebo prerazeni hlavni jizdy mimo trasu se automaticky vybere jina existujici jizda dane trasy; pokud zadna nezbyva, `main_ride_id` se nastavi na `NULL`.
Nahradni jizda se vybere deterministicky podle nejdrivejsiho `start_time`, pri shode podle nejnizsiho `id`.

### Strategie ulozeni vypoctu

- Originalni GPX soubor zustava nemenny a je zdrojem pravdy pro GPS body a jejich casy.
- Do SQLite se ukladaji odvozene hodnoty (`start_time`, `duration_seconds`, `distance_meters`, `avg_speed_kmh`), aby byly rychle dostupne pro seznamy, statistiky a vyber nejlepsi jizdy.
- Pri ukonceni zaznamu, importu, prerazeni jizdy nebo zmene start/cil pozice se odvozene hodnoty znovu vypoctou z originalniho GPX pred ulozenim zmeny do SQLite.
- Cistena GPX kopie se zatim nevytvari. Zabranuje se tim problemum se synchronizaci mezi originalem a kopii a setri se uloziste.
- Pro budouci realtime porovnavani se budou pozice predchozich jizd dopoctavat z originalnich GPS bodu a jejich timestampu. V aktualnim case se najde odpovidajici bod nebo interpolovana pozice podle casu od trimovaneho startu.
- Stejny mechanismus umozni zobrazit, jakou vzdalenost cyklista ujel v predchozich jizdach v okamziku, kdy je na aktualni jizde. Upravene start/cil body a detekovane pauzy se zohledni pred vypoctem casove osy jizdy.
- Pokud by cteni a vypocty z originalnich GPX byly pri realtime provozu prokazatelne prilis pomale, lze pozdeji pridat odvozeny cache soubor. Originalni GPX ale musi zustat zachovany jako zdroj pravdy.

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
- **Nove (pro aktivni trasu):**
  - `active_route_id` (INTEGER, nullable, FK na `Routes.id`) - aktualne aktivni trasa; `NULL` = zadna trasa neni aktivni

Tyto konstanty uzivateli umozni:
- Vypnout autodetekci, pokud ji nechce (pause_detection_enabled = 0)
- Upravit citlivost detekce podle svych potreby (napr. delsi minimalni cekani pro semafory v meste)

### Migrace existujicich dat

1. Vytvorit novou verzi tabulky `Rides` s nullable `route_id`, protoze SQLite bezne neumoznuje odstranit `NOT NULL` z existujiciho sloupce primym `ALTER TABLE`.
2. Rozsirit tabulku `Routes` o `main_ride_id INTEGER NULL` jako nullable referenci na `Rides.id` a zachovat `NULL` pro nove nebo dosud neinicializovane trasy.
3. Prekopirovat existujici jizdy do nove tabulky a zachovat jejich ID, metadata a GPX cesty.
4. Existujici jizdy s `route_id = 0` prevest na `route_id = NULL`, pokud jde o dosavadni nezarazene jizdy.
5. Pro existujici trasy s jizdami doplnit hlavni jizdu deterministicky podle nejdrivejsiho `start_time`, pri shode podle nejnizsiho `id`; pro trasy bez jizd ponechat `NULL`.
6. Zachovat existujici GPX soubory a cesty.
7. Doplnit databazovou verzi a migracni test vcetne foreign-key vazby a deterministickeho vyberu.
8. Overit, ze migrace je opakovatelna a nesmaze zadnou jizdu.

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

1. Uzivatel ve sprave tras aktivuje trasu (checkbox/prepinac u polozky).
2. Aktivace se ulozi perzistentne do `Settings.active_route_id`; predchozi aktivni trasa se deaktivuje.
3. START na Live Map vytvori novou jizdu s aktualne aktivni trasou - vyber se na Live Map neprovadi.
4. Pokud neni aktivni zadna trasa, jizda se ulozi jako nezarazena (`route_id = NULL`).
5. Po restartu aplikace se aktivni trasa obnovi ze `Settings`.

### Ulozeni jizdy

1. START zahaji zaznam v aktualne aktivni trase.
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
3. Aplikace zkontroluje, ze cilova trasa ma jmeno a pred prirazenim provede kontrolu GPX proti explicitnim hranicim nebo implicitnim hranicim hlavni jizdy cilove trasy v tolerancnim kruhu.
4. Pri neuspechu se cilova trasa nenastavi a jizda zustane nezarazena (`route_id = NULL`).
5. Aktualizuje se pouze `route_id` a pripadne `updated_at` v SQLite; **GPX soubor v adresari `gpx/` se nepresouva** - stejny soubor zustava na miste.
6. Pokud cilova trasa nema hlavni jizdu, prvni uspesne prirazena jizda se nastavi jako `main_ride_id`.
7. **Prepocita se trimovani podle start/end pozic nove trasy:**
   - Pokud je nova trasa ma nastavene start a end pozice, aplikace parsuje GPX
   - Najde prvni bod pro start pozici a posledni bod pred end pozici
   - Prepocita: `start_time`, `duration_seconds`, `distance_meters`
   - Aktualizuje se `updated_at`
8. Pokud je presouvana jizda hlavni jizdou puvodni trasy, vybere se nahradni jizda podle nejdrivejsiho `start_time`, pak nejnizsiho `id`; pokud zadna nezbyva, nastavi se `main_ride_id = NULL`.
9. Pokud puvodni uzivatelska trasa po presunu nema zadnou jizdu, nabidne se jeji archivace nebo smazani.
10. Jizda nikdy nesmi zmizet kvuli tomu, ze se stala neza razenou.

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

### Hlavni jizda

- Detail trasy oznaci aktualni hlavni jizdu a umozni u kazde jizdy kontextovou akci "Set as main ride for route".
- Zmena hlavni jizdy se nejprve validuje proti explicitnimu startu/cili nebo implicitnim hranicim nove hlavni jizdy; pri neuspechu se hlavni jizda nezmeni.
- Pokud je hlavni jizda smazana nebo presunuta mimo trasu, aplikace vybere nahradu podle nejdrivejsiho `start_time`, pak nejnizsiho `id`; pokud zadna jizda nezbyva, ulozi `main_ride_id = NULL`.
- Hlavni jizda neurcuje modrou caru nejrychlejsi jizdy; modra cara se stale vybera podle nejnizsiho `duration_seconds`.

### Live Map napojeni

Doplnit:

- zobrazeni jmena aktivni trasy (nebo informace, ze zadna neni aktivni) v hornim panelu,
- vykresleni GPX stopy jizdy s nejlepsim casem na aktivni trase (modra cara),
- zobrazeni start/cil markeru aktivni trasy, pokud jsou nastaveny,
- jasnou informaci, kdy se jizda uklada do "Nezarazene jizdy",
- zabraneni zmene aktivni trasy uprostred aktivniho zaznamu,
- bezpecne chovani pri navratu na Live Map.

Live Map jiz nema tlacitko pro vyber trasy - vyber a aktivace probiha vyhradne v Route Management.

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
7. Pridat persistentni aktivni trasu (`Settings.active_route_id`) a UI pro jeji aktivaci/deaktivaci v Route Management.
8. Implementovat seznam tras vcetne zvyrazneni aktivni trasy.
9. Implementovat detail trasy a seznam jizd.
10. Implementovat vytvoreni a editaci trasy, vcetne nastaveni start a end pozic (s prepocitanim trimovani jizd).
11. Implementovat validaci prirazeni proti explicitnim nebo implicitnim hranicim a inicializaci `main_ride_id` prvni uspesnou jizdou.
12. Implementovat presun, export a mazani jizd (s aktualizaci trimovani pri zmene trasy a deterministickou nahradou hlavni jizdy).
13. Implementovat volbu hlavni jizdy v detailu trasy vcetne akce "Set as main ride for route" a validace pred zmenou.
14. Napojit Live Map na aktivni trasu: zobrazeni jmena, vykresleni nejlepsi jizdy (modra cara) a start/cil markeru; odstranit vyber trasy z Live Map.
15. Implementovat Ride Statistics jako statickou tabulku jizd aktivni trasy (razeni podle casu, sloupce dle specifikace vyse).
16. Implementovat import GPX jizd pres systemovy vyber souboru (vcetne validace pred prirazenim; bez zavislosti na dalsich krocich, lze i drive kvuli testovani).
17. Doplnit migracni, servisni a widget testy.
18. Aktualizovat README a APP_REQUIREMENTS po dokonceni faze.

## Plan validace na zarizeni

### 1. Migrace databaze

1. Nainstalovat aktualni debug APK nad existujici aplikaci s daty z predchozi verze.
2. Spustit aplikaci a overit, ze se otevre bez chyby SQLite migrace.
3. Overit, ze existujici trasy, jizdy, Settings a aktivni trasa zustaly zachovany.
4. Overit, ze kazda existujici trasa s jizdami ma nastaveny `main_ride_id`; prazdna trasa ma `NULL`.

### 2. Import a aktivni trasa

1. Vytvorit prazdnou trasu a oznacit ji jako aktivni.
2. Importovat jednu validni GPX jizdu ze systemoveho vyberu souboru.
3. Overit, ze jizda patri do aktivni trasy a automaticky se stala hlavni jizdou.
4. Importovat dalsi podobnou jizdu; overit, ze je automaticky prirazena k aktivni trase.
5. Importovat vzdalenou jizdu; overit, ze zustane neza razena a aplikace nabidne "Add anyway".
6. Zvolit "Add anyway" pro jednu odmitnutou jizdu a "Keep unassigned" pro jinou; overit oba vysledky v Route Management.

### 3. Hranice trasy

1. Bez explicitniho startu/cile overit, ze se pouziva prvni/posledni bod hlavni jizdy s implicitni toleranci 100 m.
2. Nastavit start a cil z mapy a overit zobrazeni zelenych/cervenych tolerancnich kruhu na Live Map.
3. Pokusit se priradit jizdu, ktera neprojde startem nebo cilem; overit, ze prirazeni selze.
4. Pokusit se priradit jizdu, ktera prochazi obema explicitnimi kruhy; overit, ze se priradi.

### 4. Hlavni jizda a mapa

1. V detailu trasy overit vizualni oznaceni hlavni jizdy.
2. Zmenit hlavni jizdu akci "Set as main ride for route".
3. Otevrit Live Map a overit, ze modra cara odpovida nove hlavni jizde, ne nejrychlejsi jizde.
4. Presunout hlavni jizdu do jine trasy a overit automatickou volbu nahrady.
5. Smazat hlavni jizdu posledni v trase a overit `main_ride_id = NULL`.

### 5. Statistiky a zobrazeni jizd

1. Overit, ze Ride Statistics zobrazuje jen jizdy aktivni trasy, serazene podle `duration_seconds`.
2. Overit poradove cislo, vzdalenost, prumernou rychlost a ztratu oproti prvni jizde.
3. Otevrit libovolnou jizdu na mape; overit zelenou docasnou stopu, zachovani modre hlavni stopy a tlacitko pro ukonceni zeleneho zobrazeni.

### 6. Zaznam nove jizdy

1. S aktivni trasou nahrat kratkou jizdu prochazejici startem/cilem a overit prirazeni k trase.
2. Nahrat jizdu mimo hranice trasy a overit ulozeni jako neza razene.
3. Bez aktivni trasy nahrat jizdu a overit ulozeni jako neza razene.
4. Overit vznik GPX souboru, metadata v databazi a aktualizaci seznamu i statistik.

## Akceptacni kriteria

- Jizda bez vybrane trasy se ulozi s `route_id = NULL`.
- Nezarazene jizdy se zobrazi oddelene od uzivatelskych tras.
- Kazda uzivatelska trasa ma neprazdne jmeno.
- Kazda zobrazena uzivatelska trasa obsahuje alespon jednu jizdu.
- Uzivatel vidi pocet jizd u trasy.
- Uzivatel muze otevrit detail trasy a zobrazit jeji jizdy.
- Uzivatel muze priradit jizdu k jine trase bez ztraty GPX souboru.
- Kazde prirazeni pri ukonceni zaznamu, importu, prerazeni nebo zmene hlavni jizdy se predem overi proti explicitnim hranicim v tolerancnim kruhu, nebo proti implicitnim hranicim hlavni jizdy, pokud explicitni hranice nejsou zadane.
- Pri neuspesne validaci zustane jizda nezarazena (`route_id = NULL`); pri neuspesne zmene hlavni jizdy se puvodni hlavni jizda zachova.
- Nova trasa zacina s `main_ride_id = NULL` a prvni uspesne prirazena jizda se stane hlavni.
- Uzivatel muze vybrat jinou hlavni jizdu akci "Set as main ride for route".
- Hlavni jizda se pri smazani nebo presunu nahradi deterministicky podle `start_time`, pak `id`, nebo se nastavi na `NULL`, pokud nahrada neexistuje.
- Hlavni jizda je odlisna od nejrychlejsi jizdy; modra referencni cara pouziva jizdu s nejnizsim `duration_seconds`, hlavni jizda urcuje geometrii a implicitni hranice.
- Uzivatel muze smazat jizdu s potvrzenim.
- Aktivni zaznam nelze omylem prepnout do jine trasy.
- **Aktivni trasa:**
  - Nejvyse jedna trasa je aktivni soucasne; vychozi stav je zadna aktivni trasa.
  - Aktivace/deaktivace probiha vyhradne v Route Management a je vizualne zvyrazena.
  - Aktivace jine trasy automaticky deaktivuje predchozi aktivni trasu.
  - Aktivni trasa se uklada do `Settings.active_route_id` a obnovuje se po restartu aplikace.
  - Smazani aktivni trasy nastavi `active_route_id` na `NULL`.
  - Nova jizda se automaticky priradi k aktivni trase; bez aktivni trasy je jizda nezarazena.
  - Live Map nema tlacitko pro vyber trasy, pouze zobrazuje jmeno aktivni trasy.
  - Live Map vykresli modrou carou GPX jizdy s nejnizsim `duration_seconds` na aktivni trase, a start/cil markery, pokud jsou nastaveny.
  - Ride Statistics zobrazuje statickou tabulku jizd aktivni trasy serazenou podle casu, s casovou ztratou oproti nejlepsimu casu; bez aktivni trasy zobrazi vyzvu k vyberu trasy.
- **Import GPX jizd:**
  - Jeden nebo vice GPX souboru lze vybrat systemovym vyberem souboru a importovat jako nezarazene jizdy jednou akci v Route Management.
  - Importovane jizdy maji spocitane `distance_meters`, `start_time`, `end_time` a `avg_speed_kmh` z GPX bodu.
  - Uspesne importovane soubory se zkopiruji do `gpx/`; soubory bez pouzitelnych bodu se neulozi a uzivatel je informovan.
  - Import nesmaze ani neprepise jiz existujici jizdy v databazi.
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

### Vyresene otazky (aktivni trasa)

- Nejlepsi cas na trase = nejnizsi `duration_seconds` (ciste trvani bez pauz), ne nejvyssi prumerna rychlost ani nejkratsi vzdalenost.
- Smazani aktivni trasy nastavi `Settings.active_route_id` na `NULL` (zadna trasa neni aktivni), bez blokovani mazani.
- Ride Statistics bez aktivni trasy zobrazi prazdny stav s vyzvou "Vyberte aktivni trasu ve Sprave tras" (nezobrazuje se tabulka nezarazenych jizd).
- Staticka tabulka jizd a modra stopa nejlepsi jizdy patri do Phase 2; zivy ranking a virtualni zavodnici zustavaji ve Phase 3.
