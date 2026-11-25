# @makechart/venn

Venn / Euler diagram for makechart.

## data

one row per combination, `sets` names the sets joined by `&` ( also `∩ | + , 、`, or `separator` ), `size` the amount:

    sets,size
    Trial users,580
    Paying users,463
    Trial users & Paying users,168

 - `value: inclusive` ( default ): `A` is everyone in A, `A & B` everyone in both. `exclusive`: `A` is only those in A alone.
 - without `size` bound each row counts 1, so raw records ( one row per person ) work too.
 - `label` ( optional ): on a single-set row it's the set's display name; on a combination row, the region's name.
 - dataframes ( `setRaw({frames})` ) animate; in dot style the dots move between regions.

## dev

    npm run build                # src -> dist
    npm run test:dev             # mctest with local base / chart
    npm run test:dev:serve       # UI + /playground
