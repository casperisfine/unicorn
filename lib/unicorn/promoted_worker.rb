# -*- encoding: binary -*-

class Unicorn::PromotedWorker
  attr_reader :pid, :worker

  def initialize(pid, worker, expected_worker_processes)
    @pid = pid
    @worker = worker
    @worker_processes = 0
    @expected_worker_processes = expected_worker_processes
    @ready = false
  end

  def ready?
    @ready
  end

  def ready!
    @ready = true
  end

  def promote
    @worker.soft_kill(:URG)
  end

  def scale(old_master_worker_processes)
    diff = @expected_worker_processes -
      old_master_worker_processes -
      @worker_processes

    if diff > 0
      diff.times { kill(:TTIN) }
      @worker_processes += diff
    end
  end

  def kill(sig)
    Process.kill(sig, @pid)
  end
end
