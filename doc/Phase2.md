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

- `route_id` - volitelne; `NULL` znamena nezarazenou jizdu
- `gpx_file_path`
- `start_time`, `end_time`
- `distance_meters`
- `avg_speed_kmh`
- `user_nick`
- `created_at`

Jizda muze byt ulozena bez vazby na trasu. Pri nevybrane nebo nezname trase se pouzije `route_id = NULL`; jizda se nesmi ztratit kvuli chybejicimu kontextu.

SQLite cizi klic s nullable `route_id` tuto variantu podporuje. Dotazy pro nezarazene jizdy musi pouzivat `WHERE route_id IS NULL`, ne `route_id = ?`.

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
4. GPX soubor se ulozi do adresare odpovidajiciho identifikatoru trasy a jizdy.
5. Pri chybe ulozeni se uzivateli zobrazi chyba a jizda zustane v pameti nebo v obnovitelnem stavu.
6. Pokud je kontext trasy neznamy, ulozi se jizda jako nezarazena (`route_id = NULL`).

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
4. Aktualizuje se pouze `route_id`; GPX soubor se neprepise, pokud to neni nutne.
5. Pokud puvodni uzivatelska trasa po presunu nema zadnou jizdu, nabidne se jeji archivace nebo smazani.
6. Jizda nikdy nesmi zmizet kvuli tomu, ze se stala nezaazenou.

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
- `RouteManagementScreen` - seznamy, formulare a akce

Prednost ma existujici service/singleton styl projektu. Novy `RouteService` pridat pouze pokud zjednodusi pravidla vyberu a presunu jizd.

## Poradi implementace

1. Ujasnit a migrovat databazove schema tras a jizd na nullable `route_id`.
2. Implementovat bezpecne ukladani a zobrazovani neza razenych jizd.
3. Doplnit CRUD operace pro trasy.
4. Doplnit CRUD operace a agregace pro jizdy.
5. Pridat persistentni aktualne vybranou trasu.
6. Implementovat seznam tras.
7. Implementovat detail trasy a seznam jizd.
8. Implementovat vytvoreni a editaci trasy.
9. Implementovat presun, export a mazani jizd.
10. Napojit vyber trasy na START/STOP.
11. Doplnit migracni, servisni a widget testy.
12. Aktualizovat README a APP_REQUIREMENTS po dokonceni faze.

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
- Zda se zmena trasy projevi okamzite v adresarove strukture GPX, nebo pouze v SQLite metadatech.
