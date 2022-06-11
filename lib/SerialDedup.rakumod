unit module SerialDedup;

my class SerialDedupData {
    has Semaphore $.sem is rw .= new(1);
    has $.run-queued    is rw = False;
    has $.running       is rw = False;
}

my role SerialDedupStore {
    has SerialDedupData %.serial-dedup-store-variable;
}

multi sub trait_mod:<is>(Method $r, :$serial-dedup) is export {
    my Lock $setup-lock .= new;
    $r.wrap(my method ($obj:) {
        my $d;
        $setup-lock.protect: {
            if !$obj.does(SerialDedupStore) {
                $obj does SerialDedupStore;
            }
            $d := $obj.serial-dedup-store-variable{$r.name} //= SerialDedupData.new;
        }

        if $d.sem.try_acquire() {
            my &next = nextcallee;
            $d.run-queued = False;
            if $*SERIAL_DEDUP_NO_THREADING {
                &next($obj);
                $d.sem.release();
                $obj.&$r() if $d.run-queued;
            }
            else {
                start {
                    &next($obj);
                    $d.sem.release();
                    $obj.&$r() if $d.run-queued;
                }
            }
        }
        else {
            $d.run-queued = True;
        }
    });
}

