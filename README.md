# PortalApp

PortalApp installs and manages apps on an Xbox in Developer Mode from a Windows PC or an Android phone. It talks to the console's built-in Device Portal over your home network, so nothing has to be installed on the console.

## Download

Builds for Windows and Android are on the [releases page](../../releases). On Windows, unzip the folder and run `PortalApp.exe`. On Android, open the APK and allow installs from the app you opened it with. It needs Windows 10 or later, or Android 7 or later.

## Connecting

Turn on Developer Mode on the console and open Dev Home, which shows the console's IP address. Type that into PortalApp on a device that is on the same network. If you set a username and password for the Device Portal, switch on Portal sign-in and enter them too. The last few addresses are remembered. Passwords are not.

## Installing and updating apps

The Store tab lists the apps on [Raccoon Dev Store](https://veroxsity.github.io/RaccoonDevStore/). Pressing Install on one downloads the package, checks it against the SHA-256 the listing publishes (when it has one) and sends it to the console. When the store has a newer version of something you already have, the Installed tab shows a badge. An update goes over the top of the installed copy, so the app keeps its saved data.

A package you already have can be installed from the Console tab. The console only accepts signed packages and PortalApp does not sign anything, so an unsigned one is refused.

## Managing apps

Tapping an app in the Installed tab opens it. From there it can be launched, closed or deleted. Deleting also removes the app's saved data. The Files button opens its data folders, where files can be downloaded, uploaded and deleted and new folders made. The Console tab can show what the console is displaying right now.

## Licence

MIT, see [LICENSE](LICENSE). The font is Karla, under the SIL Open Font License. PortalApp is not affiliated with Microsoft or Xbox.
