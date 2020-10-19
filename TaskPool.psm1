<#
  .SYNOPSIS
  Context for Task.

  .DESCRIPTION
  The context value for current task.

  You can use this as `$using:TPContext`.
#>
class Context {
    [string]$TaskName
    [string]$ExecutionID
    [int]$RetryCount
    [int]$MaxRetry
}


<#
  .SYNOPSIS
  The task.

  .DESCRIPTION
  The task.
  See help of `Add-TPTask`.
#>
class Task {
    [string]$Name
    [int]$RetryCount = 0
    [int]$MaxRetry = 10
    [ScriptBlock]$Action
    [Object[]]$Arguments = @()
    hidden [System.Management.Automation.Job]$Job = $null
    hidden [string]$ExecutionID = ""

    <#
      .SYNOPSIS
      Start this task in background job.
    #>
    [Task]Start() {
        if (-not $this.Name) {
            throw "Name was not set"
        }

        if (-not $this.Action) {
            throw "Action was not set"
        }

        # context for task.
        # use they like a `$using:TPContext.TaskName` in the task action.
        $TPContext = [Context]@{
            TaskName = $this.Name
            ExecutionID = [GUID]::NewGUID()
            RetryCount = $this.RetryCount
            MaxRetry = $this.MaxRetry
        }

        $this.ExecutionID = $TPContext.ExecutionID

        $this.Job = Start-Job $this.Action -ArgumentList $this.Arguments -Name $this.Name

        return [Task]$this
    }

    <#
      .SYNOPSIS
      Wait until complete or fail this task, and return TaskResult.
    #>
    [TaskResult]Join() {
        try {
            return [TaskResult]@{
                Task = $this
                ExecutionID = $this.ExecutionID
                Result = ($this.Job | Wait-Job | Receive-Job -ErrorAction Stop)
                Success = $true
            }
        } catch {
            return [TaskResult]@{
                Task = $this
                ExecutionID = $this.ExecutionID
                Error = $_
                Success = $false
            }
        }
    }

    <#
      .SYNOPSIS
      Teardown this task.

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
  The result of Task.
#>
class TaskResult {
    [Task]$Task
    [string]$ExecutionID
    [Object]$Result
    [Object]$Error
    [boolean]$Success
}


<#
  .SYNOPSIS
  The set of running Task.

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
  The event handler manager.

  .EXAMPLE
  C:\PS> $em = [EventManager]::new()
  C:\PS> $em.Add({ Write-Host "handler A: $_" })
  C:\PS> $em.Add({ Write-Host "handler B: $_" })
  C:\PS> $em.Invoke("foobar")
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
      Add new event handler.
    #>
    [void]Add([ScriptBlock]$Handler) {
       $this.Handlers.Add($Handler)
    }

    <#
      .SYNOPSIS
      Remove a handler from this event.
    #>
    [void]Remove([ScriptBlock]$Handler) {
        $this.Handlers.Remove($Handler)
    }

    <#
      .SYNOPSIS
      Invoke this event.
    #>
    [void]Invoke([Object]$Context) {
        foreach ($cb in $this.Handlers) {
            $Context | % $cb
        }
    }
}


<#
  .SYNOPSIS
  The task scheduler.

  .DESCRIPTION
  The task scheduler.
  See help of `New-TPTaskPool`.
#>
class TaskPool {
    [int]$NumSlots
    [EventManager]$OnTaskComplete
    [EventManager]$OnTaskError
    hidden [System.Collections.Queue]$Queue
    hidden [RunningTaskSet]$Running

    TaskPool([int]$NumSlots) {
        $this.NumSlots = [Math]::Max(1, $NumSlots)
        $this.OnTaskComplete = [EventManager]::new()
        $this.OnTaskError = [EventManager]::new()
        $this.Queue = [System.Collections.Queue]::new()
        $this.Running = [RunningTaskSet]::new()

        $this | Add-Member ScriptProperty 'QueueCount' { $this.Queue.Count }
        $this | Add-Member ScriptProperty 'RunningCount' { $this.Running.Count }
        $this | Add-Member ScriptProperty 'Count' { $this.QueueCount + $this.RunningCount }
    }

    <#
      .SYNOPSIS
      Add new Task object into this task pool.
    #>
    [void]Add([Task]$Task) {
        $this.Queue.Enqueue($Task)
    }


    <#
      .SYNOPSIS
      Run all Tasks in this pool.

      .DESCRIPTION
      Run all Tasks in this pool.

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

                if ($task.MaxRetry -lt 0 -or $task.RetryCount -lt $task.MaxRetry) {
                    $task.RetryCount += 1
                    $this.Queue.Enqueue($task)
                }
            }

            $this.Running.Remove($task)
            $task.Teardown()
        }
    }
}


<#
  .SYNOPSIS
  Make a new TaskPool for execute task parallelly.

  .PARAMETER NumSlots
  Number of execute tasks in same time.

  .PARAMETER OnTaskComplete
  Callback function(s) for receive each succeed tasks result.

  .PARAMETER OnTaskError
  Callback function(s) for receive error of each task calling.

  .OUTPUTS
  An instance of TaskPool.

  .EXAMPLE
  C:\PS> $pool = New-TPTaskPool -OnTaskComplete { Write-Host $_.Result }
  C:\PS> foreach ($i in 1..10) {
  >>         Add-TPTask $pool {
  >>             param([int]$num)
  >>
  >>             "hello ${num}!"
  >>         } -Arguments @($i)
  >>     }
  C:\PS> $pool.Run()
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
function New-TaskPool {
    param(
        [int]$NumSlots = 3,
        [ScriptBlock[]]$OnTaskComplete = @(),
        [ScriptBlock[]]$OnTaskError = @()
    )

    $pool = [TaskPool]::new($NumSlots)

    $OnTaskComplete | foreach { $pool.OnTaskComplete.Add($_) }
    $OnTaskError | foreach { $pool.OnTaskError.Add($_) }

    $pool
}


<#
  .SYNOPSIS
  Make a new Task and register to TaskPool that created by `New-TPTaskPool` command.

  .PARAMETER TaskPool
  A TaskPool for register the new Task.

  .PARAMETER Action
  Something to do in the new Task.

  .PARAMETER Arguments
  Arguments for Action.

  .PARAMETER Name
  The name of this Task. It will be random value if omitted.

  .PARAMETER MaxRetry
  Maximum retry count if failing task. If less than 0, retry forever.

  .OUTPUTS
  Created new Task object.
#>
function Add-Task {
    param(
        [Parameter(Mandatory,Position=0)][TaskPool]$TaskPool,
        [Parameter(Mandatory,Position=1)][ScriptBlock]$Action,
        [Object[]]$Arguments,
        [string]$Name,
        [int]$MaxRetry = 3
    )

    if (-not $Name) {
        $Name = 'TaskPool_{0:x8}' -f (Get-Random)
    }

    $task = [Task]@{
        Name = $Name
        Action = $Action
        Arguments = $Arguments
        MaxRetry = $MaxRetry
    }
    $TaskPool.Add($task)

    $task
}
