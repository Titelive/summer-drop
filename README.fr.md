# ☀️ Summer Drop

[English](README.md) · **Français**

App Mac native (SwiftUI, Liquid Glass de macOS 26) pour envoyer des ROM N64 sur la carte SD d'une [SummerCart64](https://github.com/Polprzewodnikowy/SummerCart64) par USB-C, et les récupérer, sans Terminal et sans retirer la microSD.

## Fonctions

- **Deux panneaux** : un dossier du Mac à gauche (par défaut `iCloud Drive › Documents › Jeux › Nintendo 64`), la carte SD de la cartouche à droite. Glissez des ROM de l'un à l'autre, ou depuis le Finder. Les dossiers entiers sont acceptés.
- **Clavier** : cliquez sur un panneau, puis **⌘A** tout sélectionner, **⌘C** copier, **⌘X** déplacer (toujours confirmé ; les fichiers du Mac vont à la corbeille), **⌘V** coller dans l'autre panneau. **⌘K** pour rechercher.
- **Fiches de jeu** au survol : jaquette, écran-titre, capture, année, développeur, éditeur, genres, résumé Wikipédia, région, langues, taille et format. Pour les noms de ROM inhabituels : titres alternatifs de Wikidata, puis l'IA d'Apple sur l'appareil en dernier recours (sans clé, rien ne quitte le Mac).
- **Vos étoiles** (1 à 5), gardées sur le Mac.
- **Progression** par fichier et totale, **notifications** à la fin des transferts, au branchement de la cartouche et quand une mise à jour est prête.
- **Statistiques** : ROM envoyées et récupérées, volumes, vitesses moyennes.
- **Réglages** (⌘,) : thème Automatique / Clair / Sombre, dossier de téléchargement, emplacement de `sc64deployer`, notifications, fiches de jeu, mises à jour.
- **Tutoriel** au premier lancement (flèches pour naviguer, ⌘↩ pour terminer), rejouable depuis le menu Aide.
- **Mises à jour automatiques** depuis les versions GitHub.
- N'écrase jamais un fichier du Mac. Refuse d'accéder à la carte quand la console est allumée.

## Installer

Téléchargez **SummerDrop.dmg** dans la [dernière version](https://github.com/Titelive/summer-drop/releases/latest), ouvrez-le et glissez **Summer Drop** dans Applications. `sc64deployer` est inclus.

L'app n'est pas notariée par Apple : au tout premier lancement, ouvrez Réglages Système › Confidentialité et sécurité et cliquez sur **Ouvrir quand même** (ou `xattr -cr "/Applications/Summer Drop.app"`). Les mises à jour suivantes ne redemandent rien.

**Prérequis :** Mac Apple Silicon, **macOS 26** ou plus récent, firmware SummerCart64 2.20.0 ou plus.

## Mises à jour automatiques

L'app vérifie GitHub au lancement puis toutes les 6 heures (ou **Summer Drop › Rechercher des mises à jour…**). Si une version plus récente existe, elle télécharge l'image disque et affiche **« Version X prête · Redémarrer »**. Sans clic, elle s'installe quand vous quittez l'app.

### Publier une version

Sur GitHub : **Actions › Compiler et publier › Run workflow**, tapez un numéro (par exemple `1.5.0`) et validez. GitHub Actions compile l'app sur un Mac macOS 26, y inclut le dernier `sc64deployer` officiel, crée `SummerDrop.dmg` et publie la version.

## Compiler soi-même

Xcode 26 ou Command Line Tools à jour (`xcode-select --install`).

```bash
./build.sh              # build/Summer Drop.app
./build.sh --dmg        # crée aussi build/SummerDrop.dmg
./build.sh --install    # compile et copie dans iCloud Drive/Documents/Jeux/Analogue 3D
```

## Bon à savoir

- **Éteignez la console** avant d'accéder à la carte SD.
- `sc64deployer` n'indique pas d'avancement pendant un transfert : les barres sont **estimées** d'après la taille et le débit mesuré, et n'atteignent 100 % qu'à la vraie fin.
- Envoyer un fichier qui porte le même nom qu'un fichier de la carte le **remplace**.

## Crédits

Créé par [Titelive](https://titelive.me/prestations/) · [Offrir un café](https://buymeacoffee.com/titelive) ☕
SummerCart64 et `sc64deployer` par Mateusz Faderewski ([Polprzewodnikowy](https://github.com/Polprzewodnikowy/SummerCart64)).
Non affilié à Nintendo ni à Analogue.
