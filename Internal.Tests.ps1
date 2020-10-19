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

    Context "context variable" {
        It "TaskName" {
            $task = [Task]@{
                Name = "TaskNameTest"
                Action = {
                    "TaskName = $($using:TPContext.TaskName)"
                }
            }

            $result = $task.Start().Join()
            $task.Teardown()
            $result.Result | Should Be "TaskName = TaskNameTest"
        }

        It "ExecutionID" {
            $taskA = [Task]@{
                Name = "ExecutionIDTest_A"
                Action = {
                    "ExecutionID = $($using:TPContext.executionID)"
                }
            }
            $taskB = [Task]@{
                Name = "ExecutionIDTest_B"
                Action = {
                    "ExecutionID = $($using:TPContext.executionID)"
                }
            }

            $resultA = $taskA.Start().Join()
            $taskA.Teardown()
            $resultA.Result | Should Match "ExecutionID = [a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}"

            $resultB = $taskB.Start().Join()
            $taskB.Teardown()
            $resultB.Result | Should Match "ExecutionID = [a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}"

            $resultA.Result | Should Not Be $resultB.Result
        }

        It "RetryCount" {
            $task = [Task]@{
                Name = "RetryCountTest"
                Action = {
                    if ($using:TPContext.RetryCount -lt 1) {
                        throw "first execution"
                    }
                    "second execution"
                }
            }

            $result = $task.Start().Join()
            $task.Teardown()
            $result.Error | Should Be "first execution"

            $task.RetryCount += 1

            $result = $task.Start().Join()
            $task.Teardown()
            $result.Result | Should Be "second execution"
        }

        It "MaxRetry" {
            $task = [Task]@{
                Name = "MaxRetryTest"
                Action = {
                    "MaxRetry = $($using:TPContext.MaxRetry)"
                }
                MaxRetry = 42
            }

            $result = $task.Start().Join()
            $task.Teardown()
            $result.Result | Should Be "MaxRetry = 42"
        }
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
