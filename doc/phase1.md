Phase 1 - Rozklad na kroky:
Příprava:

1. Aktualizovat pubspec.yaml - přidat potřebné balíčky - DONE
2. Vytvořit základní projekt strukturu (folders, files) - DONE

Databáze:
3. Nastavit SQLite databázi - DONE
4. Vytvořit schema (Routes, Rides, Settings tabulky) - DONE

UI Framework:
5. Vytvořit základní navigaci (4 obrazovky - Live Map, Ride Statistics, Route Management, Settings) - DONE
6. Vytvořit bottom navigation pro přepínání - DONE

Funkčnost:
7. Settings screen - uložit Nick a periodu - DONE
8. GPS - zjistit aktuální pozici - DONE
9. Live Map screen - základní layout - DONE
10. OpenStreetMap  - zobrazit na mapě - DONE
11. START/STOP tlačítka - stav a logika - DONE
12. GPX export - uložit jízdu - PRESUNUTO do Route Management
13. Wake Lock a úsporný režim - DONE
14. Opravit zobrazeni mapy na realnem telefonu - DONE

Poznamky:
- Bod 12 (GPX export) zustava soucasti Route Management.
- Bod 13 je implementovany jako globalni app-level usporneho rezimu s nastavitelnym timeoutem.
- Phase 1 je timto uzavrena. Dalsi krok je Route Management pro pripravu tras a jizd ke srovnavani.