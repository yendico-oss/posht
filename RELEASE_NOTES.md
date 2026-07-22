# Release Notes of Posht

## 2.1.0

* Feat: CLI menu is now searchable — start typing to filter the current list (collections or requests)
* Feat: mark requests as favorites with `Ctrl+F`; favorites are pinned to the top of their collection
* Feat: toggle name ↔ usage ordering live inside the menu with `Ctrl+U`
* Feat: reworked menu navigation (breadcrumb, consistent Esc/back) built on a cross-platform key reader that behaves the same on Windows and macOS
* Fix: `Remove-ApiRequest` with `-Uri`/`-Method` (non-pipeline) threw due to a wrong `ApiRequest` constructor argument count
* Fix: clipboard action in the CLI menu now correctly emits `-PersistSessionCookie` (read the wrong property before)
* Fix: `-OrderByUsage` preference is no longer lost when navigating back through the CLI menu

## 2.0.2

* Fix: cli menu on mac os failed because of missing colors (`$Host.UI.RawUI.ForegroundColor` seems not to be available on mac)
* Fix: increased serialization depth for posht.json to 20

## 2.0.1

* Feat: change Posht banner image

## 2.0.0

* Feat: new `-SkipCertificateCheck` switch parameter which is passed trough to the `Invoke-WebRequest` function
* Feat: new `-NoHistory` switch parameter which tells Posht to **not** remember the api call
* Feat: new `-Raw` switch parameter which returns the response content as a string (Default: without thew `-Raw` parameter is a powershell object)
* Feat: new `-BearerToken` parameter which sets the Authorization header
* Feat: big improvements to CLI menu (paging, more stats, order by most used requests `Show-ApiRequest -OrderByUsage`)
* Fix: CLI menu overflow issue
* Fix: when `-PersistSessionCookie` is set the web session which is used for the next requests is stripped from possible Authorization headers (to prevent having Authorization header and Session cookies at the same time)
* Fix: save request uri in the original casing to not loose information. Especially if query args are used, it's important that we don't loose the casing information when saving the requests

## 1.0.3

* CICD: add test and deployment pipeline (no change to module code)

## 1.0.2

* Feat: Use ConvertTo-Expression (thanks to @iRon7 <https://github.com/iRon7/ConvertTo-Expression>) to properly generate Invoke-ApiRequest expression (Used in Show-ApiRequest when recreating Invoke-ApiRequest calls from saved calls)

## 1.0.1

* Feat: Add a Configfile version to be able to handle future schema changes in a better way
* Feat: Add migration support to be able to support automatic config file changes
* Fix: lowercase most of the request hashtable keys (method and path are lowercase, query args are not getting touched)

## 1.0.0

* Initial version
