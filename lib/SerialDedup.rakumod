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
    $r.wrap(my method ($obj:) {
        if !$obj.does(SerialDedupStore) {
            $obj does SerialDedupStore;
        }
        my $d := $obj.serial-dedup-store-variable{$r.name} //= SerialDedupData.new;

        if $d.sem.try_acquire() {
            my &next = nextcallee;
            if $*SERIAL_DEDUP_NO_THREADING {
                $d.run-queued = False;
                &next($obj);
                $d.sem.release();
                $obj.&$r() if $d.run-queued;
            }
            else {
                start {
                    $d.run-queued = False;
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

