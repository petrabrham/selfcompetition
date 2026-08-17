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
  gpx_filename TEXT,                   -- ← ZMĚNA: přejmenováno z gpx_file_path
  user_nick TEXT,
  saved_at TEXT NOT NULL,              -- ← NOVÉ: čas prvního GPS bodu (absolutní čas)
  start_time TEXT NOT NULL,            -- ← ZMĚNA: čas trimovaného startu (může se lišit od saved_at)
  duration_seconds INTEGER NOT NULL,   -- ← NOVÉ: čisté trvání bez pauz (v sekundách)
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
| `gpx_file_path` | TEXT | `gpx_filename` | Flat struktura: `gpx/nick_YYYY-MM-DD_HH-MM-SS.gpx` |
| `start_time` | TEXT | TEXT (trimovaný) | Může se lišit od `saved_at` když se definuje start pozice |
| `end_time` | TEXT | ODSTRANĚNO | Redundantní, lze vypočítat z `start_time + duration_seconds` |
| `created_at` | TEXT | ODSTRANĚNO | Nahrazeno `saved_at` (čas prvního bodu) |
| **`saved_at`** | - | TEXT (NOVÉ) | Absolutní čas prvního GPS bodu |
| **`duration_seconds`** | - | INTEGER (NOVÉ) | Čisté trvání bez detektovaných pauz |
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
  duration_seconds = (45 - 1:30) = 2610 sekund (bez pauz)
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
  pause_detection_enabled BOOLEAN DEFAULT 1,              -- ← NOVÉ
  pause_max_distance_meters INTEGER DEFAULT 20,           -- ← NOVÉ
  pause_min_duration_seconds INTEGER DEFAULT 60,          -- ← NOVÉ
  updated_at TEXT NOT NULL
)
```

**Nová pole pro autodetekci pauz:**

- `pause_detection_enabled` - Zapnout/vypnout autodetekci pauz
- `pause_max_distance_meters` - Maximální vzdálenost mezi body pro detekci pauzy (default 20m)
- `pause_min_duration_seconds` - Minimální doba pro detekci pauzy (default 60s)

**Logika:** Pokud se dva po sobě jdoucí GPS body liší méně než `pause_max_distance_meters` a čas mezi nimi je víc než `pause_min_duration_seconds`, detekuje se to jako pausa a čas se vylučuje z `duration_seconds`.

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
   ALTER TABLE Settings ADD COLUMN pause_detection_enabled BOOLEAN DEFAULT 1;
   ALTER TABLE Settings ADD COLUMN pause_max_distance_meters INTEGER DEFAULT 20;
   ALTER TABLE Settings ADD COLUMN pause_min_duration_seconds INTEGER DEFAULT 60;
   ```

### Kontrola po migraci

```sql
-- Ověřit, že nejsou žádné jízdy bez trasy (na začátku)
SELECT COUNT(*) FROM Rides WHERE route_id IS NULL;

-- Ověřit korektnost duration_seconds
SELECT id, start_time, duration_seconds FROM Rides LIMIT 5;

-- Ověřit, že Settings má nová pole
SELECT pause_detection_enabled, pause_max_distance_meters, pause_min_duration_seconds FROM Settings WHERE id = 1;
```

---

## Budoucí verze

Tato dokumentace se rozšíří při přidávání nových verzí. Postupuj podle schématu výše.

