module IOHelper
  def  self.stderr_read
    r, w = IO.pipe
    old_stdout = STDERR.clone
    STDERR.reopen(w)
    data = ''
    t = Thread.new do
      data << r.read
    end
    begin
      yield
    ensure
      w.close
      STDERR.reopen(old_stdout)
    end
    t.join
    data
  end
end
