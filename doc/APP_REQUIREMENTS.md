# SelfCompetition - Aplikační Requirements

## 📋 Přehled aplikace

**Název aplikace:** Self Competition

_Aplikace pro sledování a srovnávání cyklistických jízd_

## 🎯 Core Features (Prioritizováno)
- [ ] Živá mapa zobrazující GPS pozici
- [ ] Přepínání mezi obrazovkami (Live Map / Ride Statistics)
- [ ] **Aktivní trasa** (perzistentní, nejvýše jedna, nastavuje se v Route Management)
- [ ] Srovnávání aktuální jízdy s předchozími jízdami
- [ ] **Real-time srovnávání během jízdy** (zobrazení aktuálního pořadí)
- [ ] Základní statistiky jízd (vzdálenost, čas, porovnání)
- [ ] Správa tras (vytvoření nové, výběr z uložených)
- [ ] Správa jízd (seznam jízd na trase, smazání)
- [ ] Import/Export jízd do formátu GPX
- [ ] Offline zobrazení tras a jízd
- [ ] Nastavení aplikace (uživatelské preference)
- [ ] Úprava jízd (nastavení startu a cíle na mapě)
- [ ] Záznam jízdy (Start / Pause / Stop tlačítka)
- [ ] Ukládání jízdy (zápis do GPX souboru a databáze po zastavení)
- [ ] **Úspora energie** (Wake Lock, automatické vypínání displeje, probouzení)

## 📱 Obrazovky

### 1. Live Map (Hlavní obrazovka)
- Zobrazuje živou mapu s GPS pozicí uživatele a virtuální pozicí z (vybraných) ostatních jízd
- Mapa se automaticky centruje na aktuální pozici
- Na hlavni obrazovce se ukazuje: aktualni cas, aktualni doba jizdy, ujeta vzdalenost, celkova vzdalenost, poradi, ztrata na nejrychlejsiho, ztrata na jizdu prede mnou
- Možnost přepnutí na druhou obrazovku (Ride Statistics)
- **Aktivní trasa se na Live Map pouze zobrazuje, nevybírá se zde:**
  - Výběr a aktivace trasy probíhá výhradně na obrazovce Route Management.
  - Live Map nemá tlačítko pro výběr trasy.
  - Jméno aktivní trasy (nebo informace, že žádná není aktivní) se zobrazuje v horním panelu.
- **Vykreslení nejlepší jízdy na aktivní trase:**
  - Pokud je aktivní trasa nastavena a má alespoň jednu jízdu, na mapě se modrou čarou vykreslí GPX trasa jízdy s nejkratším `duration_seconds`.
  - Pokud má aktivní trasa nastavený start a/nebo cíl (`start_lat/lon`, `end_lat/lon` nejsou `NULL`), zobrazí se odpovídající markery.
  - Pokud není žádná trasa aktivní, ani pokud aktivní trasa nemá žádnou jízdu, mapa žádnou stopu ani markery nezobrazuje.
- **Real-time údaje během jízdy:**
  - Aktuální vzdálenost, čas, rychlost
  - **Aktuální pořadí: "X/Y"** (např. "5/10" = aktuálně 5. místo z 10 jízd)
  - Časová ztráta/zisk oproti nejrychlejsi jízdě na dane Trase
  - TBD - Motivační indikátor (barva - zeleně když se zlepšuje, červeně když se horší)
- **Virtuální závodníci** na mapě (pozice ostatních jízd v reálném čase)
- **Orientace mapy:**
  - Režim **Free** (volné otáčení mapy)
  - Režim **North Up** (sever vždy nahoře)
  - Režim **Course Up** (automatické otáčení podle směru jízdy) - **TBD, doplnit později**
- **Cache mapových podkladů:**
  - Stažené mapové dlaždice se ukládají lokálně do cache zařízení.
  - Při opakovaném zobrazení stejné oblasti se přednostně použijí dlaždice z cache.
  - Již načtená oblast mapy musí být dostupná i bez internetového připojení.
  - Cache má mít omezenou velikost nebo možnost ručního vymazání, aby nekontrolovaně nerostla.
- **Ovládání záznamu jízdy:**
  - Tlačítko **START** - spustí záznam nové jízdy
  - Tlačítko **PAUSE** - pozastaví záznam (GPS body se zaznamenávají dále, ale čas běží)
  - Tlačítko **STOP** - zastaví záznam a uloží jízdu do GPX + databáze
- **Úspora energie během jízdy:**
  - Po čase nastaveném v Settings přejde aplikace do úsporného režimu i bez aktivního nahrávání.
  - Úsporný režim se chová stejně na obrazovkách Live Map, Ride Statistics, Route Management i Settings a není závislý na aktivním nahrávání.
  - Úsporný režim zobrazí černý overlay, nastaví jas okna na 0 a použije Android `PARTIAL_WAKE_LOCK`, aby GPS a potřebné zpracování mohly pokračovat.
  - Při zapnutém nahrávání zůstává GPS aktivní i při vypnuté obrazovce nebo na pozadí.
  - Při vypnutém nahrávání běží GPS pouze při aktivně zobrazené Live Map.
  - Úsporný režim se probouzí dotykem obrazovky; první dotyk pouze probudí aplikaci a neprovede žádnou akci pod overlayem.
  - Stisknutí Power tlačítka je systémová akce a může aktivovat zamykací obrazovku s PINem nebo gestem.
  - Při odchodu do jiné aplikace se aplikace nesnaží obcházet zabezpečení telefonu; pokud Android aktivuje zámek obrazovky, vyžádá standardní PIN, gesto nebo jiný nastavený způsob odemknutí.
  - Ovládání WiFi, Bluetooth a NFC aplikace nepřebírá; jejich vypínání řeší uživatel nebo systém.

### 2. Ride Statistics (Tabulka jízd aktivní trasy)
- Zobrazuje tabulku všech jízd **aktivní trasy**, seřazenou podle času jízdy (od nejrychlejší).
- Pokud není žádná trasa aktivní, obrazovka zobrazí prázdný stav s výzvou "Vyberte aktivní trasu ve Správě tras".
- Sloupce tabulky pro každou jízdu:
  - Datum a čas jízdy
  - Vzdálenost (km, na 1 desetinné místo)
  - Čas jízdy (`duration_seconds`, formát HH:mm)
  - Průměrná rychlost (km/h)
  - Časová ztráta oproti nejrychlejší jízdě na aktivní trase (rozdíl `duration_seconds` oproti nejlepší jízdě; u nejlepší jízdy je ztráta 0)
- Možnost přepnutí zpět na Live Map
- Živý ranking, virtuální závodníci a real-time porovnávání během jízdy zůstávají ve Phase 3 - tato obrazovka je statický přehled uložených jízd.

### 3. Route Management (Správa tras a jízd)
- Výběr již uložené trasy pro trasování
- Vytvoření nové trasy jízdou (během jízdy se vytvoří nová trasa)
- Seznam všech jízd na vybrané trase
- **Aktivace trasy:**
  - Uživatel může u libovolné trasy nastavit ji jako aktivní (např. checkbox nebo přepínač u položky trasy).
  - Aktivní je nejvýše jedna trasa současně; aktivací jiné trasy se předchozí aktivní trasa automaticky deaktivuje.
  - Uživatel může aktivní trasu i deaktivovat, čímž se aplikace vrátí do stavu "žádná trasa není aktivní".
  - Aktivní trasa je v seznamu vizuálně odlišena (zvýraznění nebo zaškrtnutý stav).
  - Aktivní trasa se ukládá perzistentně (`Settings.active_route_id`) a obnovuje se po restartu aplikace.
  - Smazání aktivní trasy nastaví `active_route_id` zpět na `NULL` (žádná trasa není aktivní).
  - Nová jízda se automaticky přiřadí k aktivní trase; pokud žádná trasa není aktivní, jízda se uloží jako nezařazená (`route_id = NULL`).
- **Úprava trasy:**
  - Nastavit startovní pozici na mapě
  - Nastavit cílovou pozici na mapě
  - Při výpočtu statistik se jízdy zarovnají/oříznou podle těchto pozic:
    - Jízda začíná od prvního průchodu startovní pozicí
    - Jízda končí posledním průchodem cílovou pozicí
  - Pokud start/cíl nejsou zadány: jízdy se používají jak jsou
- Možnosti pro každou jízdu:
  - Zobrazit offline (bez internetu)
  - Exportovat do GPX formátu
  - Importovat GPX formát
  - Smazat jízdu
- **Hromadný import GPX jízd (pro testování a rychlé naplnění dat):**
  - GPX soubory se připraví do adresáře `gpx_import/` (např. přes `adb push`)
  - Akce "Import GPX" v Route Management naimportuje všechny nalezené soubory jako nezařazené jízdy
  - Pro každou jízdu se spočítá vzdálenost, čas a průměrná rychlost z GPX bodů
  - Úspěšně importované soubory se přesunou do `gpx/`; neplatné zůstanou v `gpx_import/` a uživatel je informován souhrnnou hláškou

### 4. Settings (Nastavení)
- **Uživatelský profil:**
  - Nick uživatele
- **Záznam jízdy:**
  - Perioda ukládání bodů (interval v sekundách/metrech)
  - Minimální vzdálenost pro uložení bodu (GPS přesnost)
- **Detekce pauz v záznamu:**
  - Povolit autodetekci pauz (on/off toggle)
  - Maximální vzdálenost pro detekci pauzy (default: 20 metrů) - pokud se GPS bod pohne méně než tuto vzdálenost, považuje se za stejné místo
  - Minimální doba pro detekci pauzy (default: 60 sekund) - pokud se čas mezi body změní více než tuto dobu, považuje se za pauzu
- **Zobrazení dat:**
  - Počet zobrazovaných jízd na porovnání (Live Map a Ride Statistics)

## 🎮 Uživatelské akce (Use Cases)

### Záznam jízdy
1. Uživatel volitelně nastaví aktivní trasu v Route Management (nebo ponechá žádnou aktivní)
2. Klikne na Live Map → tlačítko **START**
3. Aplikace začne zaznamenávat GPS body dle nastaveného intervalu
4. Nová jízda se automaticky přiřadí k aktivní trase; pokud žádná trasa není aktivní, jízda bude nezařazená
5. Uživatel vidí v reálném čase:
   - Svou pozici na mapě
   - Virtuální pozice ostatních (konkurentů)
   - **Aktuální pořadí (X/Y)** - motivace ke zlepšení
   - Časový rozdíl oproti jízdě na vyšší pozici
6. Uživatel může kterýmkoli okamžikem kliknout **PAUSE** (např. čekání na semaforu)
7. Po zastavení klikne **STOP**
8. Aplikace uloží jízdu do adresáře `gpx/` a metadata do SQLite (včetně přiřazené aktivní trasy nebo `route_id = NULL`)

### Porovnání jízd
1. Po ukončení jízdy se automaticky přepne na Ride Statistics
2. Aplikace zobrazí tabulku jízd aktivní trasy seřazenou podle času jízdy
3. Uživatel vidí, jak si stojí oproti nejrychlejší jízdě (časová ztráta ve sloupci tabulky)

### Motivace a gamifikace
- **Real-time ranking:** Uživatel vidí svou pozici během jízdy → motivuje k překonávání svých limitů
- **Virtuální konkurence:** Pohled ostatních závodníků na mapě → vizuální motivace
- **Časový rozdíl:** Ukazuje přesně, o kolik sekund/minut se musí zlepšit
- **Indikátor trendu:** Barva signalizuje, zda se zlepšuje (zelená) nebo zhoršuje (červená)

## 💾 Data Model

### Ukládání dat
- **Jízdy:** Ukládány ve formátu **GPX** (jeden soubor = jedna jízda)
  - Struktura: `data/routes/{route_id}/rides/{ride_id}.gpx`
  - Obsahuje GPS body se souřadnicemi, časy, nadmořské výšky
  
- **Metadata:** **SQLite databáze** (lokálně v aplikaci)
  - Tabulka `Routes` (trasy):
    - ID trasy, název, popis
    - Startovní pozice (lat, lon)
    - Cílová pozice (lat, lon)
    - Datum vytvoření
    - **Toleranční poloměr** (max. odchylka od trasy v metrech) - pro detekci "stejné trasy"
    
  - Tabulka `Rides` (jízdy):
    - ID jízdy, ID trasy
    - Cesta k GPX souboru
    - Datum a čas jízdy
    - Čas startu, čas konce
    - Vzdálenost, průměrná rychlost
    - Nick uživatele
    
  - Tabulka `Settings` (uživatelská nastavení):
    - Nick uživatele
    - Perioda ukládání bodů
    - Minimální vzdálenost pro uložení
    - Počet zobrazovaných jízd
    - **`active_route_id`** - volitelný odkaz na aktuálně aktivní trasu (`NULL` = žádná trasa není aktivní)
    - Ostatní preference

### Detekce trasy
- Aplikace by měla tolerovat **drobné objizďky a odchylky** od trasy
- Jízda se počítá za stejnou trasu, pokud:
  - Startuje v **blízkosti startovní pozice** (podle tolerančního poloměru)
  - Končí v **blízkosti cílové pozice** (podle tolerančního poloměru)
  - GPS body jsou do určité **vzdálenosti od ideální trasy** (koridor okolo trasy)

### Offline funkčnost
- Všechna data (GPX + SQLite) uložena lokálně na zařízení
- Mapové dlaždice již navštívených oblastí jsou dostupné z lokální cache i bez internetu
- Při nedostupném internetu aplikace zobrazí dostupnou cache a nesmí kvůli tomu spadnout
- Aplikace funguje bez internetového připojení
- Při exportu se GPX soubor sdílí (email, cloud, atd.)

## 🔧 Technické Requirements

### Flutter/Dart
- **Flutter:** 3.44.9+ (Stable)
- **Dart:** 3.12.2+
- **Minimální Android API:** Level 21 (Android 5.0)
- **Target Android API:** 37 (Android 14+)
- **NDK:** 28.2.13676358

### Klíčové Flutter Balíčky
- **geolocator** - Sledování GPS pozice v reálném čase
- **google_maps_flutter** - Mapové zobrazení s markerů (virtuální závodníci)
- **sqflite** - SQLite databáze pro metadata tras a jízd
- **geoxml** nebo **gpx** - Čtení a zápis GPX souborů
- **path_provider** - Přístup k aplikačním složkám na zařízení
- **intl** - Formátování data, času a čísel
- **wakelock_plus** - Partial Wake Lock (CPU běží, obrazovka off)
- **screen** - Kontrola zapínání/vypínání displeje

### Android Oprávnění (AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
```

### Performance
- Real-time GPS update dle periody nastavené v Settings
- Hladké animace virtuálních závodníků na mapě
- Efektivní SQLite dotazy pro výpočet statistik
- Caching mapových tiles pro offline zobrazení

### Úspora energie během záznamu
- **Partial Wake Lock** - CPU a GPS mohou pokračovat při vypnutém displeji
- **Automatické vypínání displeje** - po nastaveném čase nečinnosti se použije černý overlay a jas 0
- **Minimální jas** - pokud se obrazovka zapne, svítí s minimálním jasem (5-10%)
- **Vypnutí zbytečných funkcí:**
  - WiFi (zbytečné během jízdy)
  - Bluetooth (zbytečné)
  - NFC (zbytečné)
  - GPS zůstává zapnutý (povinný)
- **Probuzení:** První dotyk probudí aplikaci bez provedení překryté akce a návrat aplikace do popředí obnoví jas a obsah
- **Výsledek:** Dlouhá výdrž baterie + pořád se zaznamenává GPS poloha

### Offline Funkčnost
- SQLite databáze dostupná offline
- Google Maps offline (cached tiles)
- GPX soubory dostupné bez internetu

## 📊 Fáze vývoje / Milestones

### Phase 1: MVP (Minimální funkční verze)
**Cíl:** Základní záznam jízdy a ukládání
- [x] Jednoduchá mapa (bez virtuálních závodníků)
- [x] Záznam jízdy: START/STOP (bez PAUSE)
- [x] Uložení do GPX souboru
- [x] Základní SQLite databáze (Routes, Rides tabulky)
- [x] Jednoduchý Settings screen (Nick, perioda ukládání)
- [x] Úspora energie (Wake Lock, vypínání displeje)
- **Doba:** 2-3 týdny

### Phase 2: Správa Tras a Jízd
**Cíl:** Organizace a úprava dat, aktivní trasa, statické statistiky
- [x] Route Management screen
- [x] Vytvoření nové trasy / Výběr stávající
- [x] Seznam jízd na trase (včetně nezařazených)
- [x] Smažení jízd
- [x] Přeřazení jízdy mezi trasami / do nezařazených
- [x] Hromadný import GPX jízd z `gpx_import/` (nezařazené jízdy, pro testování)
- [x] Nastavení startu/cíle trasy na mapě
- [ ] **Aktivní trasa** - výběr a perzistence (`Settings.active_route_id`), zvýraznění v seznamu tras
- [ ] Live Map: vykreslení nejlepší jízdy aktivní trasy (modrá stopa) a start/cíl markerů
- [ ] Ride Statistics screen: statická tabulka jízd aktivní trasy (čas, vzdálenost, průměrná rychlost, ztráta na nejlepší čas)
- [ ] Pause button v záznamu
- **Doba:** 2 týdny

### Phase 3: Real-time Srovnávání
**Cíl:** Motivace během jízdy nad připravenými trasami a uloženými jízdami
- [ ] Virtuální závodníci na mapě
- [ ] Real-time ranking (X/Y)
- [ ] Časový rozdíl oproti vyšší pozici
- [ ] Motivační indikátor (barva - zelená/červená)
- **Doba:** 2-3 týdny

### Phase 4: Import/Export & Offline
**Cíl:** Sdílení a offline funkčnost
- [ ] Export jízdy do GPX
- [ ] Import GPX souboru
- [ ] Offline zobrazení map (cached tiles)
- [ ] Offline SQLite (bez internetového připojení)
- **Doba:** 1-2 týdny

### Phase 5: Polish & Advanced
**Cíl:** Doladění a extra features
- [ ] Testování a debugging
- [ ] UI/UX vylepšení
- [ ] Notifikace (chybí GPS, slabý signál, atd.)
- [ ] Detekce trasy (tolerance koridor)
- [ ] Performance optimizace
- [ ] Stabilizace a bug fixes
- **Doba:** 1-2 týdny

**Celkový odhad:** 8-12 týdnů k plně funkční aplikaci

## 📝 Poznámky
<!-- Různé poznámky a úvahy -->
