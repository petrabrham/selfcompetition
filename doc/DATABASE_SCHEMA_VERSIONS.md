# Databázové schéma - Historie verzí

Tento dokument popisuje strukturu databáze v jednotlivých verzích. Verze je uložena v SQLite metadatech a automaticky se kontroluje při startu aplikace.

---

## Verze 2 (aktuální - před Phase 2)

Aplikace: `version: 2` v `openDatabase()`

### Tabulka `Routes`

Definuje trasy, které si uživatel vytvoří.

```sql
CREATE TABLE Routes(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT,
  start_lat REAL NOT NULL,
  start_lon REAL NOT NULL,
  end_lat REAL NOT NULL,
  end_lon REAL NOT NULL,
  tolerance_radius REAL DEFAULT 50.0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
```

**Poznámky:**
- `start_lat`, `start_lon`, `end_lat`, `end_lon` jsou povinné (`NOT NULL`)
- Každá trasa musí mít definované začátek a konec
- `tolerance_radius` - poloměr kolem start/end bodů (default 50 metrů)

---

### Tabulka `Rides`

Zaznamenané jízdy (GPS záznamy).

```sql
CREATE TABLE Rides(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  route_id INTEGER NOT NULL,
  gpx_file_path TEXT,
  start_time TEXT NOT NULL,
  end_time TEXT,
  distance_meters REAL DEFAULT 0.0,
  avg_speed_kmh REAL DEFAULT 0.0,
  user_nick TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (route_id) REFERENCES Routes(id)
)
```

**Poznámky:**
- `route_id` je povinný (`NOT NULL`) - každá jízda musí být přiřazena k trase
- `gpx_file_path` - cesta k GPX souboru (např. `data/routes/1/rides/ride_123.gpx`)
- `created_at` - čas vytvoření záznamu v databázi
- `end_time` - čas ukončení jízdy (volitelné)

---

### Tabulka `Settings`

Uživatelská nastavení (singleton - jen jeden řádek).

```sql
CREATE TABLE Settings(
  id INTEGER PRIMARY KEY,
  user_nick TEXT,
  gps_update_interval_ms INTEGER DEFAULT 1000,
  min_distance_threshold_meters REAL DEFAULT 5.0,
  num_rides_to_display INTEGER DEFAULT 3,
  screen_off_timeout_seconds INTEGER DEFAULT 30,
  updated_at TEXT NOT NULL
)
```

**Poznámky:**
- `id` je vždy 1 (singleton pattern)
- `user_nick` - přezdívka uživatele
- `gps_update_interval_ms` - interval ukládání GPS bodů
- `min_distance_threshold_meters` - minimální vzdálenost pro nový bod
- `num_rides_to_display` - kolik jízd se zobrazuje na srovnání
- `screen_off_timeout_seconds` - timeout pro zhasnutí obrazovky

---

## Verze 3 (Phase 2)

Aplikace: `version: 3` v `openDatabase()`

### Změny oproti verzi 2

#### Tabulka `Routes` - změny

```sql
CREATE TABLE Routes(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT,
  start_lat REAL,           -- ← ZMĚNA: povoluje se NULL
  start_lon REAL,           -- ← ZMĚNA: povoluje se NULL
  end_lat REAL,             -- ← ZMĚNA: povoluje se NULL
  end_lon REAL,             -- ← ZMĚNA: povoluje se NULL
  tolerance_radius REAL DEFAULT 50.0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
```

**Důvod:** Uživatel může vytvořit trasu bez konkrétního startu/cíle. Definuje je až později nebo vůbec.

---

#### Tabulka `Rides` - ZÁSADNÍ ZMĚNY

```sql
CREATE TABLE Rides(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  route_id INTEGER,                    -- ← ZMĚNA: povoluje se NULL (nezařazené jízdy)
  gpx_file_path TEXT,
  user_nick TEXT,
  saved_at TEXT NOT NULL,              -- ← NOVÉ: čas prvního GPS bodu (absolutní čas)
  start_time TEXT NOT NULL,            -- ← ZMĚNA: čas trimovaného startu (může se lišit od saved_at)
  end_time TEXT,
  duration_seconds INTEGER,            -- ← Kompatibilní původní sloupec hrubého trvání
  recorded_duration_seconds INTEGER,   -- ← Hrubé trvání mezi trimovaným startem a koncem
  clean_duration_seconds INTEGER,      -- ← Čisté trvání po trimování a pauzách; NULL před zpracováním
  distance_meters REAL DEFAULT 0.0,
  avg_speed_kmh REAL DEFAULT 0.0,
  updated_at TEXT NOT NULL,            -- ← NOVÉ: čas poslední úpravy (audit trail)
  FOREIGN KEY (route_id) REFERENCES Routes(id)
)
```

**Klíčové změny:**

| Sloupec | Verze 2 | Verze 3 | Důvod |
|---------|---------|---------|-------|
| `route_id` | NOT NULL | NULL povoleno | Nezařazené jízdy |
| `gpx_file_path` | TEXT | TEXT | Název souboru ve flat struktuře `gpx/` |
| `start_time` | TEXT | TEXT (trimovaný) | Může se lišit od `saved_at` když se definuje start pozice |
| `end_time` | TEXT | TEXT | Čas trimovaného konce |
| `created_at` | TEXT | TEXT | Čas vytvoření databázového záznamu |
| **`saved_at`** | - | TEXT (NOVÉ) | Absolutní čas prvního GPS bodu |
| **`recorded_duration_seconds`** | - | INTEGER (NOVÉ) | Hrubé trvání mezi trimovaným startem a koncem |
| **`clean_duration_seconds`** | - | INTEGER (NOVÉ) | Čisté trvání po odečtení pauz; NULL dokud není zpracováno |
| **`updated_at`** | - | TEXT (NOVÉ) | Čas poslední úpravy (trimování, přesuny) |

**Příklad:**

```
Uživatel zapne záznam:          saved_at = 14:30:00
Čeká 10 minut:                  [body v GPX]
Reálně vyjíždí:                 start_time = 14:40:00
Jede 45 minut:                  [45 minut cyklování]
Při semaforu (1:30 čekání):     [detektováno jako pausa]
Jede dál 5 minut:               [5 minut cyklování]
Vypne záznam:                   [posledn GPX bod]

Výsledek:
  saved_at = 14:30:00
  start_time = 14:40:00 (trimovaný start)
  recorded_duration_seconds = 2790 sekund
  clean_duration_seconds = 2610 sekund (bez pauz)
  updated_at = 2026-01-15T22:30:00Z (čas poslední úpravy)
```

---

#### Tabulka `Settings` - přidání polí

```sql
CREATE TABLE Settings(
  id INTEGER PRIMARY KEY,
  user_nick TEXT,
  gps_update_interval_ms INTEGER DEFAULT 1000,
  min_distance_threshold_meters REAL DEFAULT 5.0,
  num_rides_to_display INTEGER DEFAULT 3,
  screen_off_timeout_seconds INTEGER DEFAULT 30,
  show_clean_duration BOOLEAN DEFAULT 1,                  -- ← NOVÉ
  pause_radius_meters REAL DEFAULT 20.0,                  -- ← NOVÉ
  pause_min_duration_seconds INTEGER DEFAULT 90,          -- ← NOVÉ
  updated_at TEXT NOT NULL
)
```

**Nová pole pro zobrazení a autodetekci pauz:**

- `show_clean_duration` - Preferovat čistý čas před hrubým časem ve statistikách a budoucím realtime UI
- `pause_radius_meters` - Poloměr prostoru, ve kterém se jízda považuje za stojící (default 20m)
- `pause_min_duration_seconds` - Minimální doba stání pro detekci pauzy (default 90s)

**Logika:** Algoritmus použije kotvící bod pauzy a sleduje následné GPS body, dokud zůstávají v `pause_radius_meters`. Pokud takový úsek trvá nejméně `pause_min_duration_seconds`, čas se vyloučí z `clean_duration_seconds`. Tím se správně zpracují opakované body v importovaném GPX i časové mezery v řídce zaznamenané vlastní jízdě.

---

## Migrace z verze 2 na verzi 3

### Kroky migrace

1. **Routes tabulka** - dovolení NULL pro start/end:
   ```sql
   ALTER TABLE Routes MODIFY start_lat NULL;
   ALTER TABLE Routes MODIFY start_lon NULL;
   ALTER TABLE Routes MODIFY end_lat NULL;
   ALTER TABLE Routes MODIFY end_lon NULL;
   ```
   *Poznámka: SQLite nepodporuje MODIFY, bude třeba vytvořit novou tabulku a zkopírovat data.*

2. **Rides tabulka** - úplné přepsání:
   - Vytvořit novou tabulku s novým schématem
   - Kopírovat stávající data:
     ```sql
     INSERT INTO Rides_new (id, route_id, gpx_filename, user_nick, saved_at, start_time, duration_seconds, distance_meters, avg_speed_kmh, updated_at)
     SELECT id, route_id, gpx_file_path, user_nick, created_at, start_time, CAST((julianday(end_time) - julianday(start_time)) * 86400 AS INTEGER), distance_meters, avg_speed_kmh, created_at
     FROM Rides;
     ```
   - Stará tabulka se přejmenuje a nová se pojmenuje `Rides`

3. **Settings tabulka** - přidání nových sloupců:
   ```sql
  ALTER TABLE Settings ADD COLUMN show_clean_duration INTEGER DEFAULT 1;
  ALTER TABLE Settings ADD COLUMN pause_radius_meters REAL DEFAULT 20.0;
  ALTER TABLE Settings ADD COLUMN pause_min_duration_seconds INTEGER DEFAULT 90;
   ```

### Kontrola po migraci

```sql
-- Ověřit, že nejsou žádné jízdy bez trasy (na začátku)
SELECT COUNT(*) FROM Rides WHERE route_id IS NULL;

-- Ověřit hrubý a čistý čas
SELECT id, start_time, recorded_duration_seconds, clean_duration_seconds FROM Rides LIMIT 5;

-- Ověřit, že Settings má nová pole
SELECT show_clean_duration, pause_radius_meters, pause_min_duration_seconds FROM Settings WHERE id = 1;
```

---

## Verze 9 (Phase 3 - materializovaná časová osa)

Aplikace: `version: 9` v `openDatabase()`

### Tabulka `ComparisonTimelinePoints`

Odvozená data pro rychlé realtime porovnání jízd. Zdroj pravdy zůstává GPX soubor; řádky této tabulky lze kdykoli znovu vytvořit.

```sql
CREATE TABLE ComparisonTimelinePoints(
  ride_id INTEGER NOT NULL,
  point_index INTEGER NOT NULL,
  elapsed_clean_seconds REAL NOT NULL,
  elapsed_recorded_seconds REAL NOT NULL,
  distance_meters REAL NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  altitude_meters REAL,
  speed_mps REAL,
  PRIMARY KEY (ride_id, point_index),
  FOREIGN KEY (ride_id) REFERENCES Rides(id)
)
```

Indexy `ride_id, elapsed_clean_seconds` a `ride_id, elapsed_recorded_seconds` podporují rychlý dotaz na vzdálenost historické jízdy při aktuálním čase. Body se obnovují při přepočtu jízdy, tedy také po úpravě hranic trasy nebo parametrů detekce pauz. Po migraci se aktivní trasa materializuje při prvním otevření živého porovnání.

---

## Budoucí verze

Tato dokumentace se rozšíří při přidávání nových verzí. Postupuj podle schématu výše.

