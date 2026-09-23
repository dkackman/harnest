## #302: LTX-2.5 templates don't set result.subfolder, so list_gallery(subfolder="final") returns nothing for their deliverables (same class as #235)
filed by: @dkackman

**tool/endpoint:** templates/ltx2/* (all three checked), list_gallery

**repro:** ran all three LTX-2.5 templates end to end. Each one's final `result` block saves with `subfolder: ""`. `list_gallery(subfolder="final")` — the mechanism the dw skill documents as the way to list only deliverables, separate from intermediate/working files — returns nothing for any of the three.

**expected:** LTX-2.5 templates' terminal `result` step should set `subfolder: "final"` (or whatever the current convention is post-#235), consistent with the fix already applied to `assemble-and-score` / `dissolve-between-shots` in #235.

**actual:** all three ship `subfolder: ""`, so a caller following the documented "list only deliverables" pattern gets an empty result and has to fall back to listing everything and guessing which file is the real output.

**why it matters:** this looks like the same defect class #235 fixed, just not propagated to the LTX-2.5 template family — worth checking whether other template families were missed too.
