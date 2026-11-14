# The export is shared as data, so AirDrop names it "comma-separated values-….csv"

Settled on 2026-11-14 by the owner (device check S11, then a picker: "Revert #253 for now").

Export sessions shares the CSV as data, with "Pianism sessions.csv" as its suggested name. Save to Files keeps that
name; AirDrop doesn't, and the file reaches a Mac as "comma-separated values-….csv". It opens in Numbers either way
(device check S10).

**Why:** #253 shared it as a file made when the share sheet asked for it, to keep the name over AirDrop. On the iPhone
(S11) the sheet then took several seconds to open, as iOS waited 2 s trying to open the file in place before giving
up, and AirDrop sent the data as text, "text-….txt". The owner: "not sure a file name is worth a 2 s wait when it
appears correctly in some circumstances". So #253 is reverted.

**For later:** writing the file when Export is tapped, then sharing that ready file, might keep the name without the
wait. It's untried; revisit only if the AirDrop name comes up again.
