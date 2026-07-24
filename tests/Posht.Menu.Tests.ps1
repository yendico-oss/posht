BeforeAll {
  Import-Module "$PSScriptRoot/../Posht/Posht.psd1" -Force
}

Describe 'ApiRequest.Favorite' {
  It 'defaults to false when absent from JSON' {
    InModuleScope Posht {
      $raw = @{ Method = 'Get'; BaseUri = 'http://x:80'; Path = '/a' }
      $r = [ApiRequest]::new($raw)
      $r.Favorite | Should -BeFalse
    }
  }

  It 'reads true from JSON' {
    InModuleScope Posht {
      $raw = @{ Method = 'Get'; BaseUri = 'http://x:80'; Path = '/a'; Favorite = $true }
      $r = [ApiRequest]::new($raw)
      $r.Favorite | Should -BeTrue
    }
  }
}

Describe 'ApiConfig.AddRequest favorite preservation' {
  It 'keeps Favorite and increments UsageCount when overwriting' {
    InModuleScope Posht {
      $cfg = [ApiConfig]::new()
      $r1 = [ApiRequest]::new(@{}, 'Get', 'http://x:80/a', $null, $false, $false, $false, '')
      $cfg.AddRequest($r1)
      $key = $r1.GetCollectionKey()
      $cfg.Collections['http://x:80'].Requests[$key].Favorite = $true

      $r2 = [ApiRequest]::new(@{}, 'Get', 'http://x:80/a', $null, $false, $false, $false, '')
      $cfg.AddRequest($r2)

      $stored = $cfg.Collections['http://x:80'].Requests[$key]
      $stored.Favorite    | Should -BeTrue
      $stored.UsageCount  | Should -Be 2
    }
  }
}

Describe 'Select-ApiMenuItem' {
  BeforeEach {
    $script:items = InModuleScope Posht {
      @(
        [CliMenuItem]::new('GET /users', 1),
        [CliMenuItem]::new('POST /users/login', 2),
        [CliMenuItem]::new('GET /orders', 3)
      )
    }
  }

  It 'returns all items when filter is empty' {
    InModuleScope Posht -Parameters @{ items = $script:items } {
      param($items)
      (Select-ApiMenuItem -Items $items -Filter '').Count | Should -Be 3
    }
  }

  It 'matches substring case-insensitively' {
    InModuleScope Posht -Parameters @{ items = $script:items } {
      param($items)
      $r = Select-ApiMenuItem -Items $items -Filter 'USER'
      $r.Count | Should -Be 2
      $r.Label | Should -Contain 'GET /users'
      $r.Label | Should -Contain 'POST /users/login'
    }
  }

  It 'returns empty when nothing matches' {
    InModuleScope Posht -Parameters @{ items = $script:items } {
      param($items)
      (Select-ApiMenuItem -Items $items -Filter 'zzz').Count | Should -Be 0
    }
  }
}

Describe 'Sort-ApiRequestList' {
  BeforeEach {
    $script:reqs = InModuleScope Posht {
      $a = [ApiRequest]::new(@{}, 'Get', 'http://x:80/aaa', $null, $false, $false, $false, ''); $a.UsageCount = 1
      $b = [ApiRequest]::new(@{}, 'Get', 'http://x:80/bbb', $null, $false, $false, $false, ''); $b.UsageCount = 9
      $c = [ApiRequest]::new(@{}, 'Get', 'http://x:80/ccc', $null, $false, $false, $false, ''); $c.UsageCount = 5; $c.Favorite = $true
      @($a, $b, $c)
    }
  }

  It 'puts favorites first, then name order' {
    InModuleScope Posht -Parameters @{ reqs = $script:reqs } {
      param($reqs)
      $sorted = Sort-ApiRequestList -Requests $reqs -Mode 'Name'
      $sorted[0].Path | Should -Be '/ccc'
      $sorted[1].Path | Should -Be '/aaa'
      $sorted[2].Path | Should -Be '/bbb'
    }
  }

  It 'puts favorites first, then usage desc' {
    InModuleScope Posht -Parameters @{ reqs = $script:reqs } {
      param($reqs)
      $sorted = Sort-ApiRequestList -Requests $reqs -Mode 'Usage'
      $sorted[0].Path | Should -Be '/ccc'
      $sorted[1].Path | Should -Be '/bbb'
      $sorted[2].Path | Should -Be '/aaa'
    }
  }
}

Describe 'Sort-ApiCollectionList' {
  BeforeEach {
    $script:cols = InModuleScope Posht {
      $c1 = [ApiCollection]::new('http://bbb:80', @{}); $c1.UsageCount = 2
      $c2 = [ApiCollection]::new('http://aaa:80', @{}); $c2.UsageCount = 8
      @($c1, $c2)
    }
  }

  It 'orders by name ascending' {
    InModuleScope Posht -Parameters @{ cols = $script:cols } {
      param($cols)
      (Sort-ApiCollectionList -Collections $cols -Mode 'Name')[0].BaseUri | Should -Be 'http://aaa:80'
    }
  }

  It 'orders by usage descending' {
    InModuleScope Posht -Parameters @{ cols = $script:cols } {
      param($cols)
      (Sort-ApiCollectionList -Collections $cols -Mode 'Usage')[0].BaseUri | Should -Be 'http://aaa:80'
    }
  }
}

Describe 'Invoke-ApiRequestAction' {
  It 'returns Details output separately from the nav token' {
    InModuleScope Posht {
      $r = [ApiRequest]::new(@{}, 'Get', 'http://x:80/a', $null, $false, $false, $false, '')
      $res = Invoke-ApiRequestAction -Action 'Details' -Request $r
      $res.Nav | Should -Be 'Exit'
      $res.Output | Should -Be $r
    }
  }

  It 'returns Back with no output for Cancel' {
    InModuleScope Posht {
      $r = [ApiRequest]::new(@{}, 'Get', 'http://x:80/a', $null, $false, $false, $false, '')
      $res = Invoke-ApiRequestAction -Action 'Cancel' -Request $r
      $res.Nav | Should -Be 'Back'
      $res.Output | Should -BeNullOrEmpty
    }
  }
}
