# Change Logs

## v0.0.1

 - init release: venn / euler diagram
   - `layout`: `euler` ( circle areas and pairwise overlaps follow the values ) or `venn` ( equal circles, every overlap drawn )
   - 1 ~ 3 sets drawn directly; 4+ sets as a ring where only neighbours overlap. combinations the geometry can't show
     ( non-adjacent pairs, triples in a ring ... ) fall back to separate dashed bubbles
   - `value`: rows as `inclusive` ( A = everyone in A ) or `exclusive` ( A = only A ). without `size` bound each row counts 1
   - labels: set name + total, region amount ( optional percent ), region name; each can be turned off. legend hides sets
   - `style: dot`: circles made of dots ( circle / square / person / bug ), idle motion ( jiggle / wander ).
     dots keep their identity across data updates and frames, moving to the most related region
