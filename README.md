TaskPool
========

The task scheduling module for PowerShell.


## Example

``` ps1
using module .\TaskPool


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


``` ps1
using module .\TaskPool


$pool = [TaskPool]::new(5)  # 5 tasks will be parallel execute

$pool.Add([Task]@{
    Name = "task name"
    MaxRetry = 4  # 4 times retry if fail. The first execution is not included, so total max 5 times execute.
    Arguments = @("foo", "bar")
    Action = {
        $Args -join ","
    }
})

$pool.OnTaskError.Add({
    Write-Error $_.Error
})

$pool.OnTaskComplete.Add({
    Write-Host $_.Result
})

$pool.Run()
```
