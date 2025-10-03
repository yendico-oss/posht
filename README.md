# ![Posht PS Module Banner](/assets/posht_logo_narrow.png)

As a backend (API) developer or also as a consumer of http APIs we need to do a lot of API calls. Also there is quite a lot of repetition and who wants to type `Invoke-Webrequest ...` or `curl ...`, remembering the query arguments or body, over and over again. While there are tools for that (Postman, Insomnia), I was looking for a more integrated approach. I didn't want to switch to my memory hungry Postman instance just for a single http call on my 16GB laptop already running docker workloads...

That's where the Powershell 'Posht' module comes to the rescue. Testing API is now possible directly trough Powershell. You can run it from Visual Studio Code or any other Powershell terminal. The module remembers all past requests and groups them by URL. By showing an in CLI menu it's easy to replay past requests and there are more functions to edit groups of requests (e.g. change a Header for a group of requests).

> **Posht** = swiss german expression for mail

## Prerequesites

- OS: Windows, Linux, Mac
- Powershell >= 7.2 ([How to install](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.3))

## Install module

- Open a Powershell terminal
- `Install-Module posht` (from the Powershell Gallery)
- `Import-Module posht`

## How to use

The central function of the module is **`Invoke-ApiRequest`** which is a wrapper around the Powershell native function `Invoke-WebRequest`.

```powershell
Invoke-ApiRequest -Uri <String> [-Method <String>] [-Body <Object>] [-PersistSessionCookie] [-BearerToken] [-Headers <Hashtable>] [-SaveHeadersOnCollection] [-Raw] [-SkipCertificateCheck] [-NoHistory] [<CommonParameters>]
Invoke-ApiRequest -RequestData <ApiRequest> [<CommonParameters>]
```

By using the `Invoke-ApiRequest`:

- All requests are then inventorized in the config file and grouped by Base Uri (e.g. `https://test.foo.bar:443`)
- This group of requests are called collections (`Get-ApiCollection`)
  - Headers can be defined on collection level and will apply to all requests within the collection
  - The BaseUri of a collection can be changed and will apply to all requests within the collection (e.g. switch between environments `https://test.foo.bar`, `https://dev.foo.bar`)
- Use the CLI menu to conveniently navigate between past requests: `Show-ApiRequest`

### Config / Requests File

The module creates a config & request text (Json) file in the user profile path under `/.posht/posht.json`. There are CLI commands to modify the file. **Use caution** if you edit the file directly.

Default path of the config file: `$Home/.posht/posht.json`

However it's also possible to have multiple 'local' Posht config files (For example if you want to have one per API project and take it under source control). The module will first look for a `posht.json` file in the local directory, if it can't find one, it will look in the $Home path as described above.

> If you want to create a new local config file use the New-ApiConfig function with the '-Local' switch: `New-ApiConfig -Local`

### Authenticated Requests

When you need to do authenticated requests it's possible to do either Cookie based authentication or with an Authentication header. See [Examples](#authentication-cookie-based) for the details. It's important though to tell Posht to remember the Session Cookie (`-PersistSession`) or the Authentication header (`-Headers @{Authentication="Bearer xyz"} -SaveHeadersOnCollection`) for future requests. For single requests it's possible to directly specify a bearer token with `-BearerToken xyz`.

Note: When using cookies, Posht currently only supports one active session at a time. So, if you switch between collections you most probably need to login again.

### Examples

Let's go through some examples to see how Posht works. First let's do two GET requests:

- GET Request (cat-fact): `Invoke-ApiRequest -Uri "https://cat-fact.herokuapp.com/facts/random?animal_type=cat&amount=2"`
- GET Request (open-meteo): `Invoke-ApiRequest -Uri "https://api.open-meteo.com:443/v1/forecast?latitude=47.37&longitude=8.55&current_weather=true"`

This two requests are now saved in two collections as they have different base URLs.

> **Tab completion:** As the `posht_requests.json` gets poplulated with more and more requests we can also make use of the tab completion feature for the `-Uri` and `-BaseUri` parameters.
>
> - Type => `Invoke-ApiRequest -Uri http`, Press `tab` key and you can cycle trough the suggestions
> - Type => `Get-ApiRequest -BaseUri https://cat`, Press `tab` key and you can cycle trough the suggestions

It's also possible to list all the collections or all the requests:

- Get all collections: `Get-ApiCollection`
- Get all requests: `Get-ApiRequest`

When a request is found which we would like to run again we can use the pipe (`|`) operator:

- Find request and run it again: `Get-ApiRequest | Where-Object BaseUri -like "https://cat-fact*" | Invoke-ApiRequest`

If you prefer a more menu like approach to browse trough existing collections and requests there is the CLI menu:

- Show a menu to browse collections and requests (ordered by request url and path): `Show-ApiRequest`
- If you prefer an ordering by usage (most used collections and requests on top): `Show-ApiRequest -OrderByUsage`

![Posht CLI Menu](/assets/posht_cli_menu.png)

#### Authentication (Cookie based)

- POST request to the auth endpoint and tell Posht to remember it (`-PersistSessionCookie` Parameter): `Invoke-ApiRequest -Method Post -Uri "https://foo.bar/auth" -Body @{ Username="admin"; Password="abc123" } -PersistSessionCookie`
- Check Session Cookies: `Get-ApiSessionCookie`
- Remove Session Cookies: `Clear-ApiSession`

#### Authentication (Bearer token)

- Obtain bearer token
- Do a first request with Authentication Header and tell Posht to remember it (`-SaveHeadersOnCollection` Parameter) for all requests in the same collection: `Invoke-ApiRequest -Method Get -Uri "https://foo.bar/cars" -Headers @{ Authentication="Bearer f4f4994a875d4d1ca4d13408b9e027df4" } -SaveHeadersOnCollection`
- For single requests or if you have the bearer token in a variable: `Invoke-ApiRequest -Method Get -Uri "https://foo.bar/cars" -BearerToken $token`

## Sponsors

[![yendico AG](/assets/yendico_logo_textwhite_48.png)](https://yendico.ch)
