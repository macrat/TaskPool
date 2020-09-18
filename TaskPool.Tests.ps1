using module .\TaskPool.psd1


Describe "Task" {
    It "success job" {
        $task = [Task]@{
            Name = "TaskA"
            Action = {
                $Args[0] + $Args[1]
            }
            Arguments = @(1, 2)
        }

        $result = $task.Start().Join()
        $task.Teardown()

        $result.GetType().Name | Should Be "TaskResult"
        $result.Task.Name | Should Be "TaskA"

        $result.Error | Should Be $null
        $result.Success | Should Be $true
        $result.Result | Should Be 3
    }

    It "fail job" {
        $task = [Task]@{
            Name = "TaskB"
            Action = {
                throw "error on $($Args[0])"
            }
            Arguments = "foobar"
        }

        $result = $task.Start().Join()
        $task.Teardown()

        $result.GetType().Name | Should Be "TaskResult"
        $result.Task.Name | Should Be "TaskB"

        $result.Error | Should Be "error on foobar"
        $result.Success | Should Be $false
        $result.Result | Should Be $null
    }

    It "invalid task" {
        {
            ([Task]@{
                Action = {}
            }).Start()
        } | Should Throw "Name was not set"

        {
            ([Task]@{
                Name = "hello"
            }).Start()
        } | Should Throw "Action was not set"
    }
}


Describe "EventManager" {
    It "add and remove" {
        $em = [EventManager]::new()
        $a = { Write-Host hello }
        $b = { Write-Host world }

        $em.Count | Should Be 0

        $em.Add($a)
        $em.Count | Should Be 1

        $em.Add($b)
        $em.Count | Should Be 2

        $em.Add($a)
        $em.Count | Should Be 2

        $em.Remove($a)
        $em.Count | Should Be 1

        $em.Remove($a)
        $em.Count | Should Be 1

        $em.Remove($b)
        $em.Count | Should Be 0
    }

    It "invoke" {
        $log = [System.Collections.ArrayList]::new()
        $em = [EventManager]::new()

        $em.Add({
            $log.Add("taskA($_)")
        }.GetNewClosure())

        $em.Add({
            $log.Add("taskB($_)")
        }.GetNewClosure())

        $log.Count | Should Be 0
        $log -join "," | Should Be ""

        $em.Invoke(1)
        $log.Count | Should Be 2
        $log -join "," | Should Be "taskA(1),taskB(1)"

        $em.Invoke("two")
        $log.Count | Should Be 4
        $log -join "," | Should Be "taskA(1),taskB(1),taskA(two),taskB(two)"
    }
}


Describe "TaskPool" {
    It "serial run" {
        $pool = [TaskPool]::new(1)

        foreach ($i in 1..10) {
            $pool.Add("Task $i", {
                $Args[0] * 2
            }, $i)
        }

        $result = [PSCustomObject]@{
            Log = @()
            Error = 0
        }
        $pool.OnTaskComplete.Add({
            $result.Log += $_.Result
        }.GetNewClosure())
        $pool.OnTaskError.Add({
            Write-Error $_.Error
            $result.Error += 1
        }.GetNewClosure())

        $pool.Run()

        $result.Error | Should Be 0
        $result.Log.Count | Should Be 10
        $result.Log -join "," | Should Be ((1..10 | foreach { $_ * 2 }) -join ",")
    }

    It "parallel run" {
        $pool = [TaskPool]::new(5)

        foreach ($i in 1..10) {
            $pool.Add("Task $i", {
                $Args[0] * 2
            }, $i)
        }

        $result = [PSCustomObject]@{
            Sum = 0
            Error = 0
        }
        $pool.OnTaskComplete.Add({
            $result.Sum += [int]$_.Result
        }.GetNewClosure())
        $pool.OnTaskError.Add({
            Write-Error $_.Error
            $result.Error += 1
        }.GetNewClosure())

        $pool.Run()

        $result.Error | Should Be 0
        $result.Sum | Should Be (1..10 | foreach -begin { $s = 0} -process { $s += $_ * 2 } -end { $s })
    }

    It "retry task" {
        $pool = [TaskPool]::new(50)

        foreach ($i in 1..100) {
            $pool.Add("task$i", {
                if ((Get-Random -min 1 -max 10) -eq 1) {
                    throw "something error"
                }
            })
        }

        $result = [PSCustomObject]@{
            Complete = 0
            Error = 0
        }
        $pool.OnTaskComplete.Add({
            $result.Complete += 1
        }.GetNewClosure())
        $pool.OnTaskError.Add({
            $result.Error += 1
        }.GetNewClosure())

        $pool.Run()

        $result.Error | Should BeGreaterThan 0
        $result.Error | Should BeLessThan 1000
        $result.Complete | Should Be 100
    }

    It "dynamic create task" {
        $pool = [TaskPool]::new()

        $task = {
            param([int]$count)

            if ($count -lt 5) {
                @{
                    Name = "task${count}"
                    Arguments = $count + 1
                }
            } else {
                $null
            }
        }
        $pool.Add("task1", $task, 1)

        $result = [PSCustomObject]@{
            Complete = 0
            Error = 0
        }
        $pool.OnTaskComplete.Add({
            $result.Complete += 1
            if ($_.Result -ne $null) {
                $pool.Add($_.Result.Name, $task, $_.Result.Arguments)
            }
        }.GetNewClosure())
        $pool.OnTaskError.Add({
            Write-Error $_.Error
            $result.Error += 1
        }.GetNewClosure())

        $pool.Run()

        $result.Error | Should Be 0
        $result.Complete | Should Be 5
    }
}
