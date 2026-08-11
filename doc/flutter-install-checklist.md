# Checklist instalace pro Flutter mobilni vyvoj na Windows

Tento checklist pocita s tim, ze uz mas:

- [x] Git
- [x] VS Code rozsireni Flutter

## 1. Nainstalovat Flutter SDK

- [x] Otevri oficialni stranku pro instalaci Flutter SDK pro Windows.
- [x] Stahni Flutter SDK zip.
- [x] Rozbal SDK do jednoduche cesty bez mezer, napriklad `C:\dev\flutter`.
- [x] Over, ze existuje soubor `C:\dev\flutter\bin\flutter.bat`.

## 2. Pridat Flutter do PATH

- [x] Otevri nastaveni systemove promenne `Path`.
- [x] Pridej `C:\dev\flutter\bin`.
- [x] Zavri a znovu otevri terminal ve VS Code.
- [x] Spust prikaz:

```powershell
flutter --version
```

- [x] Ocekavany vysledek: vypise se verze Flutter SDK.

## 3. Overit zakladni stav instalace

- [x] Spust prikaz:

```powershell
flutter doctor
```

- [x] Poznamenej si, ktere polozky jsou oznacene jako chybejici nebo nehotove.

## 4. Nainstalovat Android Studio

- [x] Stahni a nainstaluj Android Studio.
- [x] Pri instalaci nech zapnute Android SDK, Android SDK Platform-Tools a Android Virtual Device.
- [x] Po instalaci otevri Android Studio alespon jednou.

## 5. Doinstalovat Android SDK komponenty

- [x] V Android Studio otevri `Settings > Android SDK`.
- [x] Over, ze je nainstalovana alespon jedna stabilni Android platforma.
- [x] Over, ze jsou nainstalovane `Android SDK Command-line Tools`.
- [x] Over, ze jsou nainstalovane `Platform-Tools`.
- [x] Over, ze jsou nainstalovane `Build-Tools`.

## 6. Prijmout Android licence

- [ ] Spust prikaz:

```powershell
flutter doctor --android-licenses
```

- [x] Potvrd vsechny licence.

## 7. Znovu spustit kontrolu

- [x] Spust znovu:

```powershell
flutter doctor
```

- [x] Ocekavany stav: Flutter a Android toolchain jsou bez chyb.
- [-] Pokud zustane chyba jen pro iOS nebo Xcode, na Windows ji zatim ignoruj.

## 8. Pripravit Android telefon pro testovani

- [ ] Na telefonu zapni vyvojarske moznosti.
- [ ] Zapni `USB debugging`.
- [ ] Pripoj telefon k PC pres USB.
- [ ] Pri prvnim pripojeni povol duveru pocitaci.
- [ ] Spust prikaz:

```powershell
flutter devices
```

- [ ] Ocekavany vysledek: telefon je videt v seznamu zarizeni.

## 9. Volitelne: vytvorit emulator

- [x] V Android Studio otevri Device Manager.
- [x] Vytvor jeden emulator s beznou velikosti telefonu.
- [x] Spust emulator.
- [x] Over prikazem:

```powershell
flutter devices
```

## 10. Prvni projektovy test

- [x] Az bude vse nainstalovane, vytvor Flutter projekt.
- [x] Spust aplikaci na telefonu nebo emulatoru.
- [x] Over, ze funguje `flutter run`.

```powershell
flutter create moje_cyklo_aplikace
cd moje_cyklo_aplikace
flutter run
```

## 11. Konfigurovat SSL pro Zscaler proxy (corporate network)

> **Pouze pokud pracujes v korporatni siti s Zscaler proxy!**

V korporatni siti Zscaler interceptuje HTTPS a Gradle nema pristup k Maven repositorim bez spravne SSL konfigurace.

### Krok 1: Exportovat corporate certifikat
```powershell
# Export Zscaler Root CA z Windows Certificate Store
certutil -store -user root "Zscaler Root CA" > C:\temp\zscaler-root.cer
```

### Krok 2: Vytvořit merged PKCS12 truststore
```powershell
# JDK default certs konvertovat z JKS do PKCS12
$jdkKeystore = "C:\Program Files\Android\Android Studio\jbr\lib\security\cacerts"
$truststore = "$env:USERPROFILE\.gradle\gradle-merged-cacerts.p12"

keytool -importkeystore `
  -srckeystore $jdkKeystore `
  -srcstoretype JKS `
  -srcstorepass changeit `
  -destkeystore $truststore `
  -deststoretype PKCS12 `
  -deststorepass changeit `
  -noprompt

# Importovat Zscaler root cert do truststore
keytool -import `
  -alias zscaler-root `
  -file C:\temp\zscaler-root.cer `
  -keystore $truststore `
  -storepass changeit `
  -noprompt
```

### Krok 3: Nastavit JAVA_HOME a PATH
```powershell
# Nastavit JAVA_HOME trvale v User environment
$javaHome = "C:\Program Files\Android\Android Studio\jbr"
[Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "User")

# Pridat jbr\bin do PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*jbr\bin*") {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$javaHome\bin", "User")
}

# Ověř nastavení
[Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
```

### Krok 4: Konfigurovat Gradle truststore
Vytvoř soubor `C:\Users\<username>\.gradle\gradle.properties` (user-level) a soubor v projektu `android/gradle.properties`:

```properties
org.gradle.jvmargs=-Xmx4g -Dfile.encoding=UTF-8 -Djavax.net.ssl.trustStore=C:/Users/<username>/.gradle/gradle-merged-cacerts.p12 -Djavax.net.ssl.trustStorePassword=changeit -Djavax.net.ssl.trustStoreType=PKCS12
```

> **Pozor:** V gradle.properties MUSÍ být forward slashes `/`, i na Windows!

### Krok 5: Ověřit nastavení
```powershell
# Zavři a znovu otevři terminal!
java -version
cd C:\gitwork-pa\selfcompetition\android
.\gradlew.bat help --no-daemon
flutter run -d emulator-5554
```

Pokud se Gradle úspěšně spustí bez SSL chyb, je nastavení hotovo.

## Co budeme resit potom

- [ ] Mapa v aplikaci
- [ ] Cteni GPS polohy
- [ ] Ukladani jizd
- [ ] Import a export GPX
- [ ] Porovnani aktualni jizdy s predchozimi jizdami

## Doporuceni

- Pro prvni verzi cil jen na Android.
- Testuj co nejdriv na realnem telefonu, ne pouze v emulatoru.
- Kdyz `flutter doctor` hlasi chybu, oprav ji driv, nez vytvoris projekt.