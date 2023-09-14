# Posht

'Posht' = swiss german expression for mail

Powershell Module which helps with testing http APIs directly through powershell (Think of Postman but completely integrated into PS, no additional GUI needed). All past requests are getting saved and grouped by "BaseUrl". User can select past requests and rerun them. BaseUrl and Headers can be changed for groups of requests etc.

## Getting started

### Install Module

- Local: Import-Module .\Posht.psd1 -Force
- Remote: TODO from gitlab?

### How to use

The module creates a config/request JSON file in the directory where the commands are used (e.g. if you are in C:\temp it will create a C:\temp\api-request.json)

Use the main function to make api calls: `Invoke-ApiRequest`

- All requests are then saved in the config file and grouped by BaseUri (e.g. https://foo.bar:3222)
- This group of requests are called collections (`Get-ApiCollection`)
  - Headers can be defined on collection level and will apply to all requests within the collection
  - The BaseUri of a collection can be changed and will apply to all requests within the collection (e.g. switch between environments https://test.foo.bar, https://dev.foo.bar)
- Use the CLI menu to conveniently navigate between past requests: `Show-ApiRequest`
