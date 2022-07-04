# -*- encoding: binary -*-

# :stopdoc:
class Unicorn::ReforkOrder
  attr_accessor :nr, :worker

  def initialize(nr, worker, tmpdir)
    @nr = nr
    @worker = worker
    @tmpdir = tmpdir
  end

  # refork order objects may be compared to just plain Integers
  def ==(other_nr) # :nodoc:
    @nr == other_nr
  end

  def create_worker_child
    File.mkfifo(pipe_path)
    raw_pipe = File.open(pipe_path, IO::RDONLY | IO::NONBLOCK)
    raw_pipe.autoclose = false
    pipe = Kgio::Pipe.for_fd(raw_pipe.fileno)
    Unicorn.shrink_pipe(pipe)

    Unicorn::Worker.new(nr, [pipe, nil])
  end

  def pid
    Integer(File.read(pid_path))
  rescue Errno::ENOENT
    nil
  end

  def create_worker_parent
    return false unless File.exist?(pid_path)

    pid = Integer(File.read(pid_path))

    # open raises ENXIO if the worker no longer have the pipe open for reading (It probably is dead).
    raw_pipe = File.open(pipe_path, IO::WRONLY | IO::NONBLOCK)
    raw_pipe.autoclose = false
    pipe = Kgio::Pipe.for_fd(raw_pipe.fileno)
    Unicorn.shrink_pipe(pipe)

    worker = Unicorn::Worker.new(nr, [nil, pipe])
    worker.soft_kill(:CONT) # Pipe is open, worker can start
    worker
  end

  def close
    File.unlink(pid_path) rescue nil
    File.unlink(pipe_path) rescue nil
  end

  def register_to_parent(worker)
    Unicorn.atomic_write(pid_path, "#{$$}\n")
    cont_cb = Signal.trap(:CONT) { } # noop
    quit_cb = Signal.trap(:QUIT) { exit!(1) } # noop
    Process.kill(:URG, Process.ppid)
    worker.kgio_tryaccept(5) # Give 5 seconds to the master for opening the pipe and sending SIGCONT
    Signal.trap(:CONT, cont_cb)
    Signal.trap(:QUIT, quit_cb)
  end

  private

  def pid_path
    File.join(@tmpdir, "#{nr}.pid")
  end

  def pipe_path
    File.join(@tmpdir, "#{nr}.pipe")
  end
end
