# frozen_string_literal: true

# Fixture: a spec that never finishes. Used by the stall-diagnostics
# integration spec to prove the watchdog report and worker stack dump.
RSpec.describe "Fixture that hangs" do
  it "blocks forever on a queue" do
    $stderr.reopen(File::NULL) # simulate silent_stream swallowing $stderr
    Queue.new.pop
  end
end
