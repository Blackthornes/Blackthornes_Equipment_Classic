-- The upgrade banner can be dragged (a player asked, the owner said build
-- it, 2026-11-05): its spot is kept per character, right-click puts it
-- back at the top middle, and a drag never opens the finder.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("toastspot")

local ns = env.Load()
ns.charDB = ns.charDB or {}
local now = 100
_G.GetTime = function() return now end

local Toast = ns.Toast
-- The drop-in nudges the point a few pixels while it plays.
local function AtTop(point)
    return point and point[1] == "TOP" and math.abs(point[5] + 150) <= 12
end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) <= 12 end
local opened = 0
ns.FinderUI = ns.FinderUI or {}
ns.FinderUI.Show = function() opened = opened + 1 end

Toast:Show({ title = "Upgrade in your bags", link = "item:1" })
local frame = Toast.frame
suite.check("first shows at the top middle", AtTop(frame._point), frame._point and frame._point[5])
suite.check("it can be dragged", frame._scripts.OnDragStart ~= nil and frame._scripts.OnDragStop ~= nil)

-- Dropped somewhere else.
frame._left, frame._top = 300, 900
frame._scripts.OnDragStart(frame)
frame._scripts.OnDragStop(frame)
local spot = ns.charDB.toastSpot
suite.check("the spot is kept for this character", spot and spot[1] == 300 and spot[2] == 900,
    spot and spot[1])
suite.check("placed by its top left", frame._point[1] == "TOPLEFT" and frame._point[4] == 300
    and frame._point[5] == 900)

-- The mouse going up at the end of the drag is no click.
frame._scripts.OnClick(frame)
suite.check("a drag doesn't open the finder", opened == 0, opened)
now = now + 1
frame._scripts.OnClick(frame)
suite.check("a real click still does", opened == 1, opened)

-- The next banner comes up where it was left.
Toast:Dismiss()
frame._point = nil
Toast:Show({ title = "Upgrade in your bags", link = "item:2" })
suite.check("the next banner keeps the spot", frame._point and frame._point[1] == "TOPLEFT"
    and frame._point[4] == 300 and Near(frame._point[5], 900))

-- Right-click puts it back.
frame._scripts.OnMouseUp(frame, "RightButton")
suite.check("right-click forgets the spot", ns.charDB.toastSpot == nil)
suite.check("and it's back at the top middle", AtTop(frame._point))
frame._scripts.OnMouseUp(frame, "LeftButton")
suite.check("a left click leaves it be", frame._point[1] == "TOP")

-- A broken spot in the save is skipped.
ns.charDB.toastSpot = { "x", 5 }
Toast:Place()
suite.check("a spot that makes no sense is skipped", frame._point[1] == "TOP")
ns.charDB.toastSpot = nil
Toast:Dismiss()

suite.done()
