unit module Formatters;

sub format-dt($dt) is export {
    do with $dt {
        sprintf "%04d-%02d-%02d %02d:%02d:%02d",
            .year, .month, .day,
            .hour, .minute, .second
    }
    else {
        ""
    }
}
