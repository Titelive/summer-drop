# ☀️ Summer Drop

Petite app Mac native (SwiftUI, style Liquid Glass de macOS 26) pour envoyer des ROM N64 sur la carte SD d'une [SummerCart64](https://github.com/Polprzewodnikowy/SummerCart64) par USB-C, sans passer par le Terminal.

Elle remplace « SC64 Envoi » (version 1, script bash + boîtes de dialogue AppleScript).

## Ce qu'elle fait

- **Glisser-déposer** : déposez une ou plusieurs ROM dans la zone de gauche (ou cliquez sur « Choisir des fichiers… »). Elles partent dans le dossier de la carte affiché à droite.
- **Contenu de la carte SD** : liste des fichiers et dossiers, double-clic pour ouvrir un dossier, flèche pour remonter, bouton pour actualiser.
- **Progression** : barre par fichier et barre totale.
- **État de la cartouche** : pastille verte / rouge, vérifiée toutes les 3 secondes.

## Prérequis

- Mac Apple Silicon sous **macOS 26** (Tahoe) ou plus récent.
- **Xcode 26** ou les **Command Line Tools** à jour (`xcode-select --install`). Le SDK macOS 26 est indispensable pour Liquid Glass.
- L'outil **`sc64deployer`** (firmware SC64 2.20.0 ou plus).

## Installer

Téléchargez **SummerDrop.dmg** dans la [dernière version](https://github.com/Titelive/summer-drop/releases/latest), ouvrez-le et glissez **Summer Drop** dans Applications (ou dans `Jeux/Analogue 3D`). `sc64deployer` est déjà inclus dans l'app.

Au premier lancement, macOS bloque l'app car elle n'est pas notariée par Apple. Allez dans Réglages Système → Confidentialité et sécurité, puis cliquez sur **Ouvrir quand même** en bas de la page. Autre solution, dans le Terminal : `xattr -cr "/Applications/Summer Drop.app"`. Les mises à jour automatiques suivantes ne redemandent rien.

## Mises à jour automatiques

L'app vérifie les nouvelles versions publiées sur GitHub au lancement, puis toutes les 6 heures (menu **Summer Drop → Rechercher des mises à jour…** pour le faire à la main). Quand une version plus récente existe, elle télécharge l'image disque et affiche **« Version X prête · Redémarrer »**. Si vous ne cliquez pas, la mise à jour s'installe quand vous quittez l'app.

Le dépôt doit être **public** pour que l'app puisse lire les versions sans identifiants.

### Publier une nouvelle version

Sur GitHub : onglet **Actions** → **Compiler et publier** → **Run workflow**, tapez le numéro (par exemple `1.1.0`) et validez. Ou bien, en ligne de commande :

```bash
git tag v1.1.0
git push origin v1.1.0
```

GitHub Actions compile l'app sur un Mac (macOS 26), y inclut le dernier `sc64deployer` officiel, crée `SummerDrop.dmg` et publie la version. Toutes les apps installées la proposeront ensuite d'elles-mêmes.

## Compiler soi-même

Dans le Terminal :

```bash
cd "/chemin/vers/summer-drop"
./build.sh
```

L'app est créée dans `build/Summer Drop.app`.

Pour créer aussi l'image disque `build/SummerDrop.dmg` :

```bash
./build.sh --dmg
```

Pour la compiler **et** la copier directement dans `iCloud Drive/Documents/Jeux/Analogue 3D/` :

```bash
./build.sh --install
```

Le script cherche `sc64deployer` dans le dossier du projet, dans le dossier parent, puis dans `iCloud Drive/Documents/Jeux/Analogue 3D/`, et le copie dans l'app (`Contents/Resources`). Il retire la quarantaine et signe l'app localement (signature « ad hoc »).

## Où l'app cherche `sc64deployer`

Dans cet ordre :

1. le chemin choisi avec le bouton « Localiser sc64deployer… » (mémorisé) ;
2. à côté de l'app ;
3. dans l'app (`Contents/Resources`) ;
4. `iCloud Drive/Documents/Jeux/Analogue 3D/sc64deployer` ;
5. `/opt/homebrew/bin` puis `/usr/local/bin`.

## Bon à savoir

- **Éteignez la console** avant d'accéder à la carte. Si elle est allumée, `sc64deployer` refuse l'accès et l'app l'affiche clairement au lieu de forcer.
- `sc64deployer` n'indique pas d'avancement pendant un envoi : la barre de progression est **estimée** à partir de la taille du fichier et du débit mesuré aux envois précédents. Elle passe à 100 % quand l'envoi est réellement terminé.
- Un fichier qui porte le même nom qu'un fichier de la carte le **remplace**.

## Structure

```
Sources/
  SummerDropApp.swift   point d'entrée, fenêtre
  ContentView.swift     interface (Liquid Glass)
  AppModel.swift        état, file d'envoi, détection de la cartouche
  Deployer.swift        appel de sc64deployer et lecture de ses réponses
  Updater.swift         mises à jour automatiques via GitHub Releases
.github/workflows/      compilation et publication automatiques
Info.plist              métadonnées de l'app
AppIcon.icns            icône
build.sh                script de compilation
```
