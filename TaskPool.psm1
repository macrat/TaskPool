<#
  .SYNOPSIS
  The Task

  .EXAMPLE
  PS> $pool = [TaskPool]::new()
  PS> $task = [Task]@{ Name = "greeting"; Action = { Write-Host "hello world!" } }
  PS> $pool.Add($task)
  PS> $pool.Run()
  hello world!
#>
class Task {
    [string]$Name
    [int]$RetryCount = 0
    [int]$MaxRetry = 10
    [ScriptBlock]$Action
    [Object[]]$Arguments = @()
    hidden [System.Management.Automation.Job]$Job = $null

    <#
      .SYNOPSIS
      Start this task in background job
    #>
    [Task]Start() {
        if (-not $this.Name) {
            throw "Name was not set"
        }

        if (-not $this.Action) {
            throw "Action was not set"
        }

        $this.Job = Start-Job $this.Action -ArgumentList $this.Arguments -Name $this.Name

        return [Task]$this
    }

    <#
      .SYNOPSIS
      Wait until complete or fail this task, and return [TaskResult]
    #>
    [TaskResult]Join() {
        try {
            return [TaskResult]@{
                Task = $this
                Result = ($this.Job | Wait-Job | Receive-Job -ErrorAction Stop)
                Success = $true
            }
        } catch {
            return [TaskResult]@{
                Task = $this
                Error = $_
                Success = $false
            }
        }
    }

    <#
      .SYNOPSIS
      Teardown this task

      .DESCRIPTION
      [!IMPORTANT]
      Make sure call after each Start method calling.
    #>
    [Task]Teardown() {
        $this.Job | Remove-Job
        $this.Job = $null
        return $this
    }
}


<#
  .SYNOPSIS
  The result of [Task]
#>
class TaskResult {
    [Task]$Task
    [Object]$Result
    [Object]$Error
    [boolean]$Success
}


<#
  .SYNOPSIS
  The set of running [Task]

  .DESCRIPTION
  This is a internal class of the TaskPool module.
#>
class RunningTaskSet {
    hidden [HashTable]$TaskTable

    RunningTaskSet() {
        $this.TaskTable = @{}

        $this | Add-Member ScriptProperty 'Count' { $this.TaskTable.Count }
    }

    [void]Add([Task]$Task) {
        $this.TaskTable.Add($Task.Job.Id, $Task)
    }

    [void]Remove([Task]$Task) {
        $this.TaskTable.Remove($Task.Job.Id)
    }

    [Task]GetByJob([System.Management.Automation.Job]$Job) {
        return $this.TaskTable[$Job.Id]
    }

    [Task]WaitAny() {
        $jobList = $this.TaskTable.Values | foreach { $_.Job }
        return $this.GetByJob(($jobList | Wait-Job -any))
    }
}



<#
  .SYNOPSIS
  The event handler manager

  .EXAMPLE
  PS> $em = [EventManager]::new()
  PS> $em.Add({ Write-Host "handler A: $_" })
  PS> $em.Add({ Write-Host "handler B: $_" })
  PS> $em.Invoke("foobar")
  handler A: foobar
  handler B: foobar
#>
class EventManager {
    hidden [System.Collections.Generic.HashSet[ScriptBlock]]$Handlers

    EventManager() {
        $this.Handlers = [System.Collections.Generic.HashSet[ScriptBlock]]::new()

        $this | Add-Member ScriptProperty 'Count' { $this.Handlers.Count }
    }

    <#
      .SYNOPSIS
      Add new event handler
    #>
    [void]Add([ScriptBlock]$Handler) {
       $this.Handlers.Add($Handler)
    }

    <#
      .SYNOPSIS
      Remove a handler from this event
    #>
    [void]Remove([ScriptBlock]$Handler) {
        $this.Handlers.Remove($Handler)
    }

    <#
      .SYNOPSIS
      Invoke this event
    #>
    [void]Invoke([Object]$Context) {
        foreach ($cb in $this.Handlers) {
            $Context | % $cb
        }
    }
}


<#
  .SYNOPSIS
  The [Task] scheduler

  .EXAMPLE
  PS> $pool = [TaskPool]::new()
  PS> foreach ($i in 1..10) { $pool.Add("task $i", { param([int]$num) Write-Host "hello ${num}!" }, $i) }
  PS> $pool.Run()
  hello 1!
  hello 2!
  hello 3!
  hello 4!
  hello 5!
  hello 6!
  hello 7!
  hello 8!
  hello 9!
  hello 10!
#>
class TaskPool {
    [int]$NumSlots
    [EventManager]$OnTaskComplete
    [EventManager]$OnTaskError
    hidden [System.Collections.Queue]$Queue
    hidden [RunningTaskSet]$Running

    hidden Init([int]$NumSlots) {
        $this.NumSlots = $NumSlots
        $this.OnTaskComplete = [EventManager]::new()
        $this.OnTaskError = [EventManager]::new()
        $this.Queue = [System.Collections.Queue]::new()
        $this.Running = [RunningTaskSet]::new()

        $this | Add-Member ScriptProperty 'QueueCount' { $this.Queue.Count }
        $this | Add-Member ScriptProperty 'RunningCount' { $this.Running.Count }
        $this | Add-Member ScriptProperty 'Count' { $this.QueueCount + $this.RunningCount }
    }

    TaskPool([int]$NumSlots) {
        $this.Init($NumSlots)
    }

    TaskPool() {
        $this.Init(3)
    }

    <#
      .SYNOPSIS
      Add new [Task] into this task pool
    #>
    [void]Add([Task]$Task) {
        $this.Queue.Enqueue($Task)
    }

    <#
      .SYNOPSIS
      Add new [Task] into this task pool by task name, scriptblock, and argument list
    #>
    [void]Add([string]$Name, [ScriptBlock]$Action, [Object[]]$Arguments) {
        $this.Add([Task]@{
            Name = $Name
            Action = $Action
            Arguments = $Arguments
        })
    }

    <#
      .SYNOPSIS
      Add new [Task] into this task pool by task name and scriptblock
    #>
    [void]Add([string]$Name, [ScriptBlock]$Action) {
        $this.Add($Name, $Action, @())
    }


    <#
      .SYNOPSIS
      Run all [Task]s in this pool

      .DESCRIPTION
      This method will blocking until done or fail all tasks.
    #>
    [void]Run() {
        while ($this.Count -gt 0) {
            while ($this.QueueCount -gt 0 -and $this.RunningCount -lt $this.NumSlots) {
                $task = $this.Queue.Dequeue()
                $task.Start()
                $this.Running.Add($task)
            }

            $task = $this.Running.WaitAny()

            $result = $task.Join()
            if ($result.Success) {
                $this.OnTaskComplete.Invoke($result)
            } else {
                $this.OnTaskError.Invoke($result)

                if ($task.MaxRetry -le 0 -or $task.RetryCount -lt $task.MaxRetry) {
                    $task.RetryCount += 1
                    $this.Queue.Enqueue($task)
                }
            }

            $this.Running.Remove($task)
            $task.Teardown()
        }
    }
}


Export-ModuleMember -Function Task, TaskPool
