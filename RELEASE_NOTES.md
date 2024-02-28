# Release Notes of Posht

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
