[English](../../README.md) · [Português (Brasil)](README_pt-BR.md) · [Español](README_es.md) · **Français** · [Deutsch](README_de.md) · [Italiano](README_it.md)

<p align="center">
  <img src="../assets/icon.png" width="96" height="96" alt="Icône de l’app Insonia">
</p>

# Insonia

**Gardez vos agents de programmation actifs, même capot fermé.**

Insonia maintient votre Mac éveillé pendant que vos agents locaux, compilations et tests s’exécutent. Vous pouvez fermer le capot et vous éloigner sans mettre l’ordinateur en veille. Si vous suivez vos agents depuis votre téléphone par accès à distance, votre Mac peut rester disponible à la maison pendant vos déplacements.

**[Télécharger pour Mac](https://github.com/reyhenrick/insonia/releases/latest/download/Insonia-macOS.dmg)**

macOS 26 ou version ultérieure · Apple silicon et Intel · Gratuit et open source

<p align="center">
  <img src="../assets/panel.png" width="380" alt="Panneau Insonia dans la barre des menus avec Empêcher la mise en veille activé">
</p>

<a id="install-and-start"></a>

## Installation

1. Ouvrez le DMG et faites glisser **Insonia** dans **Applications**.
2. Ouvrez Insonia et cliquez sur l’éclair dans la barre des menus.
3. Activez **Empêcher la mise en veille**, autorisez la demande d’administration de macOS si elle apparaît et attendez l’activation.

L’app n’a pas été authentifiée par Apple. Si macOS bloque le premier lancement, suivez les [instructions d’Apple](https://support.apple.com/fr-fr/102445) pour l’ouvrir depuis **Réglages Système → Confidentialité et sécurité → Ouvrir quand même**.

## Utilisation avec des agents de programmation

Lancez votre agent comme d’habitude et activez **Empêcher la mise en veille** avant de fermer le capot. Désactivez cette option lorsque vous avez terminé pour rétablir la mise en veille normale.

Pour les agents qui interagissent avec les fenêtres du navigateur ou d’autres apps, activez aussi **Autoriser les agents à utiliser l’écran** avec le capot ouvert et le Mac déverrouillé. Insonia réduit la luminosité de l’écran intégré lorsque vous fermez le capot et la rétablit à sa réouverture. Le verrouillage du Mac peut interrompre cet accès visuel.

Pour accéder au Mac pendant vos déplacements, laissez-le connecté à Internet et utilisez les commandes à distance de votre agent ou votre outil habituel d’accès à distance. Insonia gère la mise en veille du Mac ; l’accès à distance se configure séparément.

Laissez le Mac sur une surface bien ventilée pendant qu’il travaille. Insonia se met en pause lorsque la batterie atteint 15 % ou moins, si le Mac est débranché, ou lorsque macOS signale une contrainte thermique importante.

## Mises à jour

Insonia recherche les mises à jour automatiquement. Utilisez **Rechercher des mises à jour…** dans le panneau pour installer une version. L’installation attend que l’option Empêcher la mise en veille soit désactivée et que la session soit terminée.

## Contribuer

Le projet est distribué sous [licence MIT](../../LICENSE). Consultez [CONTRIBUTING.md](../../CONTRIBUTING.md) pour les instructions de compilation et de contribution, ou [ouvrez une issue](https://github.com/reyhenrick/insonia/issues/new/choose) pour signaler un problème.

[Désinstaller](../../CONTRIBUTING.md#remove-a-local-installation) · [Sécurité](../../SECURITY.md) · [Versions](https://github.com/reyhenrick/insonia/releases)
