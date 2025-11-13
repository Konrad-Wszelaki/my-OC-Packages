local version_major = "1"
local version_minor = "0"

local component     = require("component")
local io            = require("io")
local event         = require("event")
local thread        = require("thread")
local computer      = require("computer")

local gpu = component.gpu
if type(gpu) ~= "table" then
    error("GPU not found, cannot proceed...")
end

local internet = component.internet
if type(internet) ~= "table" then
    error("Internet card not found, cannot proceed...")
end

local gui = require("gui")
local GUI_VERSION_MAJOR = "2"
local GUI_VERSION_MINOR = "3"
io.write("checking GUI version compat: ")
if not gui.checkVersionCompat(gui, GUI_VERSION_MAJOR, GUI_VERSION_MINOR) then
    error("GUI library version incompatible, cannot proceed...")
end
io.write("version compatible...\n")

local kwlib = require("KWLib")
local KWLIB_VERSION_MAJOR = "2"
local KWLIB_VERSION_MINOR = "2"
io.write("checking KWLib version compat: ")
if not kwlib.checkVersionCompat(kwlib, KWLIB_VERSION_MAJOR, KWLIB_VERSION_MINOR) then
    error("KWLib library version incompatible, cannot proceed...")
end
io.write("version compatible...\n")



io.write("initializing constants, variables and tables: ")
local ClockDisplayID = "ClockDisplay"

local COLOR_OUTLINE = "#CBD117"
local COLOR_NUMBERS = "#CCCCCC"
local COLOR_MINUTE  = "#CCCCCC"
local COLOR_HOUR    = "#B33D19"

local NUMBERS_PADDING       = 3
local MINUTE_HAND_PADDING   = 5
local HOUR_HAND_PADDING     = 10

local TIME_REQUEST_URL = "https://aisenseapi.com/services/v1/datetime/+0100"
local CLOCK_SLEEP_TIME = 30

local running = true
local updateThread = nil

local screens = {}
local GPU_buffer_index = 0


-- clock display function
local clockDisplay = {}

-- clock display draw function
local function drawClockDisplay(GUI, OBJECTS, ID)

    local x0 = GUI.OBJECTS[ID].x + (GUI.OBJECTS[ID].w / 2)
    local y0 = GUI.OBJECTS[ID].y + (GUI.OBJECTS[ID].h / 2)
    local r_outer = math.min(GUI.OBJECTS[ID].w, GUI.OBJECTS[ID].h) / 2

    local r_numbers = r_outer - NUMBERS_PADDING
    local r_minute  = r_outer - MINUTE_HAND_PADDING
    local r_hour    = r_outer - HOUR_HAND_PADDING

    --content:
    -- golden outline
    GUI.drawCircle(GUI, x0, y0, r_outer, 1, COLOR_OUTLINE)

    -- hour numbers display
    for i = 1, 12, 1 do
        local x = math.floor(x0 + r_numbers * math.cos((math.pi/6)*i))
        local y = math.floor(y0 + r_numbers * math.sin((math.pi/6)*i))
        gpu.setForeground(COLOR_NUMBERS)
        gpu.set(x, y, tostring(i))
    end

    -- minute hand
    local minute_hand_angle = (math.pi / 30) * GUI.OBJECTS[ID].minute
    local x = x0 + r_hour * math.cos(minute_hand_angle)
    local y = y0 + r_hour * math.sin(minute_hand_angle)
    GUI.drawLine(GUI, x0, y0, x, y, 1, COLOR_MINUTE)

    -- hour hand
    local hour_hand_angle = (math.pi / 6) * GUI.OBJECTS[ID].hour + (math.pi / 6) * (GUI.OBJECTS[ID].minute / 60)
    local x = x0 + r_hour * math.cos(hour_hand_angle)
    local y = y0 + r_hour * math.sin(hour_hand_angle)
    GUI.drawLine(GUI, x0, y0, x, y, 1, COLOR_HOUR)


end

function clockDisplay.create()
    local newClockDisplay = {}
    -- IDEA: gold, circular outline; 12 numbers for hours; short, stubby line for hour pointer; long, thin line for minute pointerE

    -- for now: test the line drawing functionality
    newClockDisplay.type    = "CustomClockDisplay"
    newClockDisplay.ID      = ClockDisplayID
    newClockDisplay.visible = true
    newClockDisplay.content = {}
    newClockDisplay.focused = false
    newClockDisplay.x = 1
    newClockDisplay.y = 1
    newClockDisplay.w = gui.WIDTH - 2
    newClockDisplay.h = gui.HEIGHT - 2
    newClockDisplay.onDraw = drawClockDisplay

    newClockDisplay.hour    = 0
    newClockDisplay.minute  = 0

    newClockDisplay.onDelete = function(gui, self)
        return true
    end

end

local function copyFromBufferToScreens()
    for index, address in pairs(screens) do
        gpu.bind(address)
        gpu.bitblt()
    end
end

local function updateClockDisplayTime()
    while running do
        local timestamp = string.sub(internet.request(TIME_REQUEST_URL)(), 28, -13)
        local hour      = tonumber(string.sub(timestamp, 1, 2))
        local minute    = tonumber(string.sub(timestamp, 4, 5))

        gui.objects[ClockDisplayID].hour    = hour
        gui.objects[ClockDisplayID].minute  = minute
        gui.redraw(gui)
        copyFromBufferToScreens()
        os.sleep(CLOCK_SLEEP_TIME)
    end
end


-- init functions
local function listScreens()
    for address in component.list("screen", true) do
        table.insert(screens, address)
    end
end

local function initializeGPUBuffer()
    GPU_buffer_index = gpu.allocateBuffer()
    gpu.setActiveBuffer(GPU_buffer_index)
end

local function initializeGUI()
    print("creating GUI...")
    -- create a header
    local header_text = "CLOCK TOWER v" .. version_major .. "." .. version_minor
    gui.addObject(gui, "Label", header_id, header_text, math.floor((WIDTH-string.len(header_text))/2), 1, string.len(header_text), 1, "none")

    -- create the clock itself
    local newClockDisplay = clockDisplay.create()
    gui.addObject(gui, "CustomClockDisplay", newClockDisplay)

    -- create update thread
    updateThread = thread.create(updateClockDisplayTime)

    -- prepare variables for buffering
    listScreens()
    initializeGPUBuffer()

    print("done")
    return true
end

-- finally, start of the script
print("Welcome to Clock Tower display v" .. version_major .. "." .. version_minor)
print("Initializing the system")
print("\n")
initializeGUI()
gui.run(gui)

running = false
return updateThread.join(CLOCK_SLEEP_TIME + 2)