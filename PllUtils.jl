using DataStructures: Queue, enqueue!, dequeue!,
                      Stack, push!, pop!

function add_my_procs(machines::Array{String,1},
                      n_local_proc::Int)

  for machine in machines
    if machine in ("hector", "lucien", "marcel", "andrew")
      addprocs(([("nicolas@$machine", :auto)]), 
               tunnel=true,
               dir="/home/nicolas/Dropbox/Git/julia-fem/",
               exename="/home/nicolas/julia-1.5.3/bin/julia",
               topology=:master_worker)

    elseif machine == "moorcock"
      addprocs(([("venkovic@moorcock", :auto)]), 
               tunnel=true,
               dir="/home/venkovic/Dropbox/Git/julia-fem/",
               exename="/home/venkovic/julia-1.5.3/bin/julia",
               topology=:master_worker)
    end
  end

  # Add local procs after remote procs to avoid issues with ClusterManagers
  addprocs(n_local_proc, topology=:master_worker) 
  
end


function dynamic_mapreduce!(func::Function,
                            redop::Function,
                            coll::Array{Int,1},
                            K::Array{Float64,2};
                            verbose=true)
 
  njobs = length(coll)
  
  pending_jobs_id = Queue{Int}()
  for job_id in 1:njobs 
    enqueue!(pending_jobs_id, job_id)
  end

  done_jobs_id = Stack{Int}()

  running_jobs_id = Dict{Int,Int}(worker => 0 for worker in workers())
  running_jobs = Dict{Int,Task}()

  while length(done_jobs_id) < njobs
    
    sleep(2)

    # Loop over running jobs
    for (worker, job_id) in running_jobs_id

      # Worker is free
      if (job_id == 0) && (length(pending_jobs_id) > 0)
        
        # Launch a new job
        new_job_id = dequeue!(pending_jobs_id)
        new_job = @async remotecall_fetch(func, worker, coll[new_job_id], coll[new_job_id])
        
        # New job was successfully launched
        if new_job.state in (:runnable, :running, :done)
          running_jobs_id[worker] = new_job_id
          running_jobs[worker] = new_job
          verbose ? println("worker $worker launched job $new_job_id.") : nothing

        # Failed to launch new job
        else
          println("worker $worker failed to launch job $new_job_id.")
          enqueue!(pending_jobs_id, new_job_id)
        end

      # Worker is (or was) busy
      elseif job_id > 0

        # Worker is done
        if running_jobs[worker].state == :done
          
          # Fetch and reduce
          K .= redop(K, fetch(running_jobs[worker]))
          push!(done_jobs_id, job_id)
          verbose ? println("worker $worker completed job $job_id.") : nothing
          
          # Free worker
          running_jobs_id[worker] = 0

        # Worker failed at completing its job
        elseif running_jobs[job_id].state == :failed
          println("worker $worker failed to complete job $job_id.")
          enqueue!(pending_jobs_id, new_job_id)
        end
      end

    end # for (worker, job_id)
  end # while length(done_jobs_id) < njobs

  return K
end
  
#n = 2_000
#K = zeros(n, n)
#K = dynamic_mapreduce!(ones, + , [n for _ in 1:20], K)