TaskPool
========

The task scheduling module for PowerShell.


## Example

``` ps1
using module .\path\to\TaskPool.psd1


$pool = [TaskPool]::new()

for ($target in @("world", "alice", "jhon", "cat", "dog")) {
    $pool.Add("greeting to ${target}", {
        param($someone)

        "hello ${someone}!"
    }, @($target))
}

$pool.OnTaskComplete.Add({
    Write-Host "$($_.Task.Name): $($_.Result)"
})

$pool.Run()  # run greeting tasks parallel (in default, run max 3 task in same time)
# OUTPUT:
#  greeting to world: hello world!
#  greeting to alice: hello alice!
#  greeting to jhon: hello jhon!
#  greeting to cat: hello cat!
#  greeting to dog: hello dog!
```
