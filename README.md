TaskPool
========

The task scheduling module for PowerShell.


## Example

``` ps1
Import-Module .\TaskPool


$pool = New-TPTaskPool -OnTaskComplete {
    Write-Host "$($_.Task.Name): $($_.Result)"
}

for ($target in @("world", "alice", "jhon", "cat", "dog")) {
    Add-TPTask $pool {
        param($someone)

        "hello ${someone}!"
    } -Arguments @($target)
}


$pool.Run()  # run greeting tasks parallel (in default, run max 3 task in same time)
# OUTPUT:
#  greeting to world: hello world!
#  greeting to alice: hello alice!
#  greeting to jhon: hello jhon!
#  greeting to cat: hello cat!
#  greeting to dog: hello dog!
```


``` ps1
Import-Module .\TaskPool


$pool = New-TPTaskPool -NumSlots 5  # 5 tasks will be parallel execute

Add-TPTask                       `
    -Pool $pool                  `
    -Action { $Args -join "," }  `
    -Arguments = @("foo", "bar") `
    -MaxRetry 4                  `
    -Name "task name"

$pool.OnTaskError.Add({
    Write-Error $_.Error
})

$pool.OnTaskComplete.Add({
    Write-Host $_.Result
})

$pool.Run()
```
