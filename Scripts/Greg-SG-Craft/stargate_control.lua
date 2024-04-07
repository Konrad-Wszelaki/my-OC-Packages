local version_major = "1"
local version_minor = "1"

local component     = require("component")
local io            = require("io")
local serialization = require("serialization")
local event         = require("event")
local thread        = require("thread")
local computer      = require("computer")

local gpu = component.gpu
if type(gpu) ~= "table" then
    error("GPU not found, cannot proceed...")
end

local stargate = component.getPrimary("stargate")
if type(stargate) ~= "table" then
    error("No stargate connected to the computer, cannot proceed...")
end

local redstone = component.getPrimary("redstone")
if type(redstone) ~= "table" then
    io.write("Warning: no redstone control detected, safety doors will not be operated!")
end

local linked_card = component.tunnel
if type(linked_card) ~= "table" then
    io.write("Warning: no linked card detected, adresses will not be updated via central control!")
end

local gui = require("gui")
local GUI_VERSION_MAJOR = "2"
local GUI_VERSION_MINOR = "1"
io.write("checking GUI version compat: ")
if not gui.checkVersionCompat(gui, GUI_VERSION_MAJOR, GUI_VERSION_MINOR) then
    error("GUI library version incompatible, cannot proceed...")
end
io.write("version compatible...\n")

local kwlib = require("KWLib")
local KWLIB_VERSION_MAJOR = "2"
local KWLIB_VERSION_MINOR = "1"
io.write("checking KWLib version compat: ")
if not kwlib.checkVersionCompat(kwlib, KWLIB_VERSION_MAJOR, KWLIB_VERSION_MINOR) then
    error("KWLib library version incompatible, cannot proceed...")
end
io.write("version compatible...\n")



io.write("initializing constants, variables and tables: ")
-- constants --
local WIDTH, HEIGHT = gpu.getResolution()
local ADDRESS_BOOK_PATH = "//usr/stargate_addresses"
local CONFIG_FILE_PATH = "//usr/stargate_control_config"
local LOCAL_NAME = nil
-- custom gui object names
local CUSTOM_POPUP_WINDOW       = "CustomPopupWindow"
local CUSTOM_SIMPLE_CONTAINER   = "CustomSimpleContainer"

local header_id = "header"
local address_book_selectlist_id = "address_book"

local redstone_max_value = {15, 15, 15, 15, 15, 15}
local redstone_min_value = {0,  0,  0,  0,  0,  0 }
-- event names
local eventStargateDialInbound  =   "sgDialIn"
local eventStargateDialOutbound =   "sgDialOut"
local eventChevronEngaged       =   "sgChevronEngaged"
local eventStargateStateChange  =   "sgStargateStateChange"
local eventIrisStateChange      =   "sgIrisStateChange"
local eventMessageReceived      =   "sgMessageReceived"
-- stargate state safety (true if safe)
local stargate_state_safety = {
    Idle       = false,
    Dialling   = false,
    Opening    = false,
    Connected  = true,
    Closing    = false,
    Offline    = false
}
-- initiated at config load
local messageHandler --TODO: load message handler from separate file, since it will likely be different for each stargate

-- variables
local target_address = stargate.localAddress()
local address_locked = false
local address_list = {}
local name_list = {} -- inverse of the address list
local stargate_door_locked = false
local stargate_last_state = nil
local address_update_timer = nil
local ADDRESS_UPDATE_TIMER_PERIOD = 300 -- time in seconds between address updates
local DATAFILE_SAVE_TIMER_PERIOD  = 60  -- time in seconds between savefile saves

local running = true
local stargateAddressUpdateThread = nil
local lastAddressUpdateTime = 0
local saveDataFileThread = nil
local lastDataSaveTime = 0
local saveRequested = false


-- whitelist and blacklist
local address_blacklist = {}
local address_whitelist = {}
local enable_blacklist  = false
local enable_whitelist  = false

-- initialization done
io.write("completed!\n")

-- stargate floodgates control
local function close_stargate_door()
    if redstone ~= nil and not stargate_door_locked then
        redstone.setOutput(redstone_max_value)
        return true
    else
        return false
    end
end
local function open_stargate_door()
    if redstone ~= nil then
        redstone.setOutput(redstone_min_value)
        return true
    else
        return false
    end
end

-- linked card control
local function send_updated_address()
    if type(linked_card) ~= "table" then return false end

    linked_card.send(serialization.serialize({[LOCAL_NAME] = stargate.localAddress()}))
end
local function check_current_address()
    -- checking disabled, since I think it will be better if we actually send the current address every time, 1 message every 5 minutes is not that much traffic...
    --if address_list["local"] == stargate.localAddress() then return nil end
    address_list["local"] = stargate.localAddress()
    send_updated_address()
    return gui.changeItemInSelectList(gui, address_book_selectlist_id, "local", "local", setTargetAddress, address_list["local"])
end

-- read from / write to address list
-- list file and table format:
--  {
--      ["local"] = {
--          ["address"] = LocalSGAddr
--      }
--      ["name1"] = {
--          ["address"] = SGAddr
--          ["blacklist"] = true/false
--          ["whitelist"] = true/false
--      }
--      ["name2"] = {
--          ["address"] = SGAddr
--          ["blacklist"] = true/false
--          ["whitelist"] = true/false
--      }
--      ...
--  }
local function read_address_list()
    address_list["local"] = stargate.localAddress()

    local saved_list = kwlib.general.dataFiles.readDataFile(kwlib, ADDRESS_BOOK_PATH, nil)
    if not saved_list then return false end
    if saved_list["local"]["address"] ~= address_list["local"] then
        send_updated_address()
        saved_list["local"]["address"] = address_list["local"]
    end
    for name, data in pairs(saved_list) do
        address_list[name] = data["address"]
        name_list[data["address"]] = name
        if data["blacklist"] == true then
            address_blacklist[data["address"]]  = true
        end
        if data["whitelist"] == true then
            address_whitelist[data["address"]]  = true
        end
    end
    return true
end

local function write_address_list()
    local data_to_save = {}
    for name, remoteAddress in pairs(address_list) do
        data_to_save[name] = {
            address = remoteAddress,
            blacklist = false,
            whitelist = false
        }
        if address_blacklist[remoteAddress] == true then
            data_to_save[name]["blacklist"] = true
        end
        if address_whitelist[remoteAddress] == true then
            data_to_save[name]["whitelist"] = true
        end
    end
    return kwlib.general.dataFiles.saveDataFile(kwlib, ADDRESS_BOOK_PATH, data_to_save, nil)
end

-- callback functions
local function dial()
    if stargate.stargateState() == "Idle" then
        if target_address then
            local ok, result = pcall(stargate.dial, target_address)
            if ok then
                return nil
            else
                gui:addObject("InfoBox", "DialFailedInfo", "slim", "DIAL FAILED", result)
                return result
            end
        end
        gui:addObject("InfoBox", "DialFailedInfo", "slim", "DIAL FAILED", "no target selected")
        return "no target selected"
    end
    gui:addObject("InfoBox", "DialFailedInfo", "slim", "DIAL FAILED", "stargate not idle")
    return "stargate not idle"
end

local function onDroppedConnection()
    address_locked = false
    return gui:removeObject(CUSTOM_POPUP_WINDOW, "dialingInfoBoxPopupID")
end

local function closeConnection()
    if stargate.stargateState() ~= "Idle" and stargate.stargateState() ~= "Closing" then
        local ok, result = pcall(stargate.disconnect)
        if ok then
            return nil
        else
            gui:addObject("InfoBox", "closeConnectionFailedInfo", "slim", "CANNOT CLOSE", result)
            return result
        end
    end
    gui:addObject("InfoBox", "closeConnectionFailedInfo", "slim", "CANNOT CLOSE", "No connection or already closing")
    return "No connection or already closing"
end

local function sendMessage(message)
    if stargate.stargateState() == "Connected" then
        local ok, result = pcall(stargate.sendMessage, message)
        if ok then
            return nil
        else
            gui:addObject("InfoBox", "messageNotSentInfo", "slim", "MESSAGE NOT SENT", result)
            return result
        end
    end
    gui:addObject("InfoBox", "messageNotSentInfo", "slim", "MESSAGE NOT SENT", "no connection")
    return "no connection"
end

local function setTargetAddress(gui, address)
    if not address_locked then
        target_address = address
        return true
    else 
        return false
    end
end

local function addNewAddress(gui, name, address)
    address_list[name] = address
    --write_address_list()
    saveRequested = true
    return gui.addItemToSelectList(gui, address_book_selectlist_id, name, name, setTargetAddress, address)
end

local function removeAddress(gui, name)
    if type(address_list[name]) == "string" then
        address_list[name] = nil
        --write_address_list()
        saveRequested = true
        return gui.removeObject(gui, "SelectListItem", address_book_selectlist_id, name)
    end
    return false
end

local function dialConfirmYes(gui, popupID)
    gui.removeObject(gui, CUSTOM_POPUP_WINDOW, popupID)
    return dial()
end

local function sendMessageConfirmYes(gui, popupID, message)
    gui.removeObject(gui, CUSTOM_POPUP_WINDOW, popupID)
    return sendMessage(message)
end

local function addAddressConfirmYes(gui, popupID, name_and_address)
    gui.removeObject(gui, CUSTOM_POPUP_WINDOW, popupID)
    return addNewAddress(gui, name_and_address.name, name_and_address.address)
end

local function removeAddressConfirmYes(gui, popupID, name)
    gui.removeObject(gui, CUSTOM_POPUP_WINDOW, popupID)
    return removeAddress(gui, name)
end

local function closeConnectionConfirmYes(gui, popupID)
    gui.removeObject(gui, CUSTOM_POPUP_WINDOW, popupID)
    return closeConnection()
end


local function generalConfirmNo(gui, popupID)
    gui.removeObject(gui, CUSTOM_POPUP_WINDOW, popupID)
end


-- custom gui object functions
local function moveObject(gui, object, xTranslate, yTranslate)
    object.x = object.x + xTranslate
    object.y = object.y + yTranslate
    if object.content then
        for i = 1, #object.content do
            object.content[i].x = object.content[i].x + xTranslate
            object.content[i].y = object.content[i].y + yTranslate
        end
    end
    return true
end

local function drawPopupWindow(gui, OBJECTS, ID)
    gpu.setBackground(gui.colors.COLOR_general_bg)
    gpu.setForeground(gui.colors.COLOR_general_fg)

    gui.clearArea(gui, OBJECTS[ID].x, OBJECTS[ID].y, OBJECTS[ID].w, OBJECTS[ID].h)

    if OBJECTS[ID].borderStyle == "slim" or OBJECTS[ID].borderStyle == "thick" then
        gui.drawBorder(gui, OBJECTS[ID].x, OBJECTS[ID].y, OBJECTS[ID].w, OBJECTS[ID].h, OBJECTS[ID].borderStyle)
    end

    if OBJECTS[ID].content[1].onDraw then
        return OBJECTS[ID].content[1].onDraw(gui, OBJECTS[ID].content, 1)
    end

    return false
end
local function popupWindowOnClick(gui, OBJECTS, ID, ...)
    if OBJECTS[ID].content[1].onClick then
        if OBJECTS[ID].content[1].focused then
            if OBJECTS[ID].content[1].focused == false then
                OBJECTS[ID].content[1].focused = true
            end
        else
            OBJECTS[ID].content[1].focused = true
        end
        return OBJECTS[ID].content[1].onClick(gui, OBJECTS[ID].content, 1, ...)
    end
    return false
end
local function popupWindowOnKeyDown(gui, OBJECTS, ID, ...)
    if OBJECTS[ID].content[1].onKeyDown then
        return OBJECTS[ID].content[1].onKeyDown(gui, OBJECTS[ID].content, 1, ...)
    end
    return false
end

local function handleClick(gui, masterObject, OBJECTS, ...)
    local args = {...}
    local xPos = args[2]
    local yPos = args[3]

    if masterObject.last_clicked_object then
        if OBJECTS[masterObject.last_clicked_object].focused then
            OBJECTS[masterObject.last_clicked_object].focused = false
        end
        masterObject.last_clicked_object = nil
    end

    for i = #OBJECTS, 1, -1 do
        if OBJECTS[i].x and OBJECTS[i].y and OBJECTS[i].w and OBJECTS[i].h then
            if xPos >= OBJECTS[i].x and xPos < (OBJECTS[i].x + OBJECTS[i].w) and yPos >= OBJECTS[i].y and yPos < (OBJECTS[i].y + OBJECTS[i].h) then
                if OBJECTS[i].onClick then
                    if OBJECTS[i].onClick(gui, OBJECTS, i, ...) == true then
                        masterObject.last_clicked_object = i
                        OBJECTS[i].focused = true
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function drawSimpleContainer(gui, container)
    for i = 1, #container.content do
        container.content[i].onDraw(gui, container.content, i)
    end
    return true
end

local function drawObject(gui, OBJECTS, ID)
    for i = 1, #OBJECTS[ID].content do
        if OBJECTS[ID].content[i].type == "Label" then
            gui.drawLabel(gui, OBJECTS[ID].content, i)
        end
        if OBJECTS[ID].content[i].type == "Button" then
            gui.drawButton(gui, OBJECTS[ID].content, i)
        end
        if OBJECTS[ID].content[i].type == "OneLineTextField" then
            gui.drawOneLineTextField(gui, OBJECTS[ID].content, i)
        end
        if OBJECTS[ID].content[i].type == "ConfirmBox" then
            OBJECTS[ID].content[i].onDraw(gui, OBJECTS[ID].content, i)
        end
    end
    return true
end

local function simpleContainerOnClick(gui, OBJECTS, ID, ...)
    return handleClick(gui, OBJECTS[ID], OBJECTS[ID].content, ...)
end
local function simpleContainerOnKeyDown(gui, OBJECTS, ID, ...)
    if OBJECTS[ID].last_clicked_object then
        if OBJECTS[ID].content[last_clicked_object] then
            if OBJECTS[ID].content[last_clicked_object].onKeyDown then
                return OBJECTS[ID].content[last_clicked_object].onKeyDown(gui, OBJECTS[ID].content, last_clicked_object)
            end
        end
        if OBJECTS[ID].content[OBJECTS[ID].last_clicked_object].type == "OneLineTextField" then
            return gui.writeInOneLineTextField(gui, OBJECTS[ID].content, OBJECTS[ID].last_clicked_object, ...)
        end
    end
    return false
end

local function drawConfirmBox(gui, OBJECTS, ID)
    gui.drawBorder(gui, OBJECTS[ID].x, OBJECTS[ID].y, OBJECTS[ID].w, OBJECTS[ID].h, 'slim')
    return drawObject(gui, OBJECTS, ID)
end

-- custom gui objects
local popupWindow = {}
function popupWindow.create(gui, popupID, borderStyle, content, title)
    local newPopupWindow = {}

    newPopupWindow.type = CUSTOM_POPUP_WINDOW
    newPopupWindow.ID = popupID
    newPopupWindow.content = {content}
    newPopupWindow.borderStyle = borderStyle
    newPopupWindow.title = title

    newPopupWindow.visible = true
    newPopupWindow.w = newPopupWindow.content[1].w + 2
    newPopupWindow.h = newPopupWindow.content[1].h + 2
    newPopupWindow.x = math.floor((WIDTH/2) - ((newPopupWindow.content[1].w/2)+1))
    newPopupWindow.y = math.floor((HEIGHT/2)- ((newPopupWindow.content[1].h/2)+1))
    newPopupWindow.onDraw = drawPopupWindow
    newPopupWindow.onClick = popupWindowOnClick
    newPopupWindow.focused = false
    newPopupWindow.onKeyDown = popupWindowOnKeyDown
    newPopupWindow.last_clicked_object = nil

    newPopupWindow.onDelete = function(gui, self)
        for i, object in pairs(self.content) do
            if type(object.onDelete) == "function" then
                object.onDelete(gui, object)
            end
        end
    end

    moveObject(gui, newPopupWindow.content[1], newPopupWindow.x + 1 - newPopupWindow.content[1].x, newPopupWindow.y + 1 - newPopupWindow.content[1].y)
    newPopupWindow.content[1].popupMaster = newPopupWindow.ID
    
    return gui.addObject(gui, CUSTOM_POPUP_WINDOW, newPopupWindow)
end

local simpleContainer = {}
function simpleContainer.create(containerID, x, y)
    local newSimpleContainer = {}

    newSimpleContainer.type = CUSTOM_SIMPLE_CONTAINER
    newSimpleContainer.ID = containerID
    
    newSimpleContainer.content = {}
    newSimpleContainer.visible = true
    newSimpleContainer.x = x
    newSimpleContainer.y = y
    newSimpleContainer.w = 1
    newSimpleContainer.h = 1
    newSimpleContainer.onClick = simpleContainerOnClick
    newSimpleContainer.focused = false
    newSimpleContainer.onDraw = drawSimpleContainer
    newSimpleContainer.onKeyDown = simpleContainerOnKeyDown
    newSimpleContainer.last_clicked_object = nil
    newSimpleContainer.popupMaster = nil

    return newSimpleContainer
end

function simpleContainer.recalculateContainerBoundary(gui, container)
    local xmin = WIDTH
    local ymin = HEIGHT
    local xmax = 1
    local ymax = 1
    for i = 1, #container.content do
        if container.content[i].x < xmin then xmin = container.content[i].x end
        if container.content[i].y < ymin then ymin = container.content[i].y end
        if container.content[i].x + container.content[i].w > xmax then xmax = container.content[i].x + container.content[i].w end
        if container.content[i].y + container.content[i].h > ymax then ymax = container.content[i].y + container.content[i].h end
    end
    container.x = xmin
    container.y = ymin
    container.w = xmax-xmin
    container.h = ymax-ymin
    return true
end

function simpleContainer.addItemToContainer(gui, container, item)
    table.insert(container.content, item)
    return simpleContainer.recalculateContainerBoundary(gui, container)
end
function simpleContainer.removeItemFromContainer(gui, container, itemID)
    for i = #container.content, 1, -1 do
        if container.content[i].ID == itemID then
            table.remove(container.content, i)
            return simpleContainer.recalculateContainerBoundary(gui, container)
        end
    end
    return false
end

local confirmBox = {}
function confirmBox.create(gui, popupMaster, confirmBoxID, yesCallback, yesCallbackArgument, noCallback, noCallbackArgument, x, y, ...)
    local args = {...}

    local newConfirmBox = {}

    newConfirmBox.type = "ConfirmBox"
    newConfirmBox.ID = confirmBoxID
    newConfirmBox.visible = true
    newConfirmBox.onClick = simpleContainerOnClick
    newConfirmBox.content = {}
    newConfirmBox.last_clicked_object = nil
    newConfirmBox.x = x
    newConfirmBox.y = y
    newConfirmBox.w = 10
    newConfirmBox.h = 4
    newConfirmBox.popupMaster = popupMaster
    newConfirmBox.onDraw = drawConfirmBox

    function newConfirmBox.yesCallback()
        yesCallback(gui, newConfirmBox.popupMaster, yesCallbackArgument)
        return true
    end
    function newConfirmBox.noCallback()
        noCallback(gui, newConfirmBox.popupMaster, noCallbackArgument)
        return true
    end

    for i = 1, #args do
        newConfirmBox.h = newConfirmBox.h + 1
        if string.len(args[i]) > newConfirmBox.w then
            newConfirmBox.w = string.len(args[i]) + 4
        end
    end

    for i = 1, #args do
        local xPos = x + math.floor((newConfirmBox.w - string.len(args[i]))/2)
        local argTextLabel = gui.createLabel(gui, confirmBoxID .. "Label"..i, args[i], xPos, y+i, string.len(args[i]), 1, "none")
        table.insert(newConfirmBox.content, argTextLabel)
    end

    local yesButton = gui.createButton(gui, confirmBoxID .. "Yes", "YES", newConfirmBox.yesCallback, x, (y+newConfirmBox.h)-3, 5, 3, "slim")
    local noButton = gui.createButton(gui, confirmBoxID .. "No", "NO", newConfirmBox.noCallback, (x+newConfirmBox.w)-4, (y+newConfirmBox.h)-3, 4, 3, "slim")

    table.insert(newConfirmBox.content, yesButton)
    table.insert(newConfirmBox.content, noButton)

    return newConfirmBox
end

local addNewAddressBox = {}
function addNewAddressBox.create(gui, newAddressBoxID, x, y)
    local newAddNewAddressBox = {}

    newAddNewAddressBox.type = "AddNewAddressBox"
    newAddNewAddressBox.ID = newAddressBoxID
    newAddNewAddressBox.visible = true
    newAddNewAddressBox.onClick = simpleContainerOnClick
    newAddNewAddressBox.content = {}
    newAddNewAddressBox.last_clicked_object = nil
    newAddNewAddressBox.focused = false
    newAddNewAddressBox.x = x
    newAddNewAddressBox.y = y
    newAddNewAddressBox.w = 40
    newAddNewAddressBox.h = 4
    newAddNewAddressBox.popupMaster = nil
    newAddNewAddressBox.onDraw = drawObject
    newAddNewAddressBox.onKeyDown = simpleContainerOnKeyDown

    function newAddNewAddressBox.onAdd()
        local name = gui.getTextFromOneLineTextField(gui, newAddNewAddressBox.content, newAddressBoxID .. "NameField")
        local address = gui.getTextFromOneLineTextField(gui, newAddNewAddressBox.content, newAddressBoxID .. "AddressField")
        local confirmAdd = confirmBox.create(
            gui, 
            newAddNewAddressBox.popupMaster,
            newAddNewAddressBox.ID .. "ConfirmAddBox",
            addAddressConfirmYes,
            {name = name, address = address},
            generalConfirmNo,
            nil,
            (WIDTH/2)-8,
            (HEIGHT/2)-2,
            "Add new address?",
            "name: " .. name,
            "address: " .. address
        )
        return popupWindow.create(gui, "ConfirmAddAddressPopupID", "thick", confirmAdd)
    end
    function newAddNewAddressBox.onCancel()
        generalConfirmNo(gui, newAddNewAddressBox.popupMaster)
        return true
    end

    local tempObject = gui.createLabel(gui, newAddressBoxID .. "NameLabel", "Name:", x+1, y+1, 8, 1, "none")
    table.insert(newAddNewAddressBox.content, tempObject)

    local tempObject = gui.createLabel(gui, newAddressBoxID .. "AddressLabel", "Address:", x+1, y+2, 8, 1, "none")
    table.insert(newAddNewAddressBox.content, tempObject)

    local tempObject = gui.createOneLineTextField(gui, newAddressBoxID .. "NameField", "-NAME-", x+9, y+1, 24, 1)
    table.insert(newAddNewAddressBox.content, tempObject)
    
    local tempObject = gui.createOneLineTextField(gui, newAddressBoxID .. "AddressField", "ABCD-EFG-HI", x+9, y+2, 24, 1)
    table.insert(newAddNewAddressBox.content, tempObject)
    
    local tempObject = gui.createButton(gui, newAddressBoxID .. "ConfirmButton", "ADD", newAddNewAddressBox.onAdd, x+33, y+1, 6, 1, "none")
    table.insert(newAddNewAddressBox.content, tempObject)
    
    local tempObject = gui.createButton(gui, newAddressBoxID .. "CancelButton", "CANCEL", newAddNewAddressBox.onCancel, x+33, y+2, 6, 1, "none")
    table.insert(newAddNewAddressBox.content, tempObject)

    return newAddNewAddressBox
end

local removeAddressBox = {}
function removeAddressBox.create(gui, removeAddressBoxID, x, y)
    local newRemoveAddressBox = {}

    newRemoveAddressBox.type = "RemoveAddressBox"
    newRemoveAddressBox.ID = removeAddressBoxID
    newRemoveAddressBox.visible = true
    newRemoveAddressBox.onClick = simpleContainerOnClick
    newRemoveAddressBox.content = {}
    newRemoveAddressBox.last_clicked_object = nil
    newRemoveAddressBox.focused = false
    newRemoveAddressBox.targetAddress = target_address
    newRemoveAddressBox.x = x
    newRemoveAddressBox.y = y
    newRemoveAddressBox.w = (name_list[newRemoveAddressBox.targetAddress]:len() < 18) and 28 or (name_list[newRemoveAddressBox.targetAddress]:len() + 10)
    newRemoveAddressBox.h = 4
    newRemoveAddressBox.popupMaster = nil
    newRemoveAddressBox.onDraw = drawObject
    newRemoveAddressBox.onKeyDown = simpleContainerOnKeyDown

    function newRemoveAddressBox.onRemove()
        local name = name_list[newRemoveAddressBox.targetAddress]
        local confirmRemove = confirmBox.create(
            gui, 
            newRemoveAddressBox.popupMaster,
            newRemoveAddressBox.ID .. "ConfirmRemoveBox",
            removeAddressConfirmYes,
            name,
            generalConfirmNo,
            nil,
            (WIDTH/2)-8,
            (HEIGHT/2)-2,
            "Remove address?",
            "name: " .. name
        )
        return popupWindow.create(gui, "ConfirmAddAddressPopupID", "thick", confirmRemove)
    end
    function newRemoveAddressBox.onCancel()
        generalConfirmNo(gui, newRemoveAddressBox.popupMaster)
        return true
    end

    local tempObject = gui.createLabel(gui, removeAddressBoxID .. "NameLabel", "Name:", x+1, y+1, 8, 1, "none")
    table.insert(newRemoveAddressBox.content, tempObject)

    local tempObject = gui.createLabel(gui, removeAddressBoxID .. "NameField", name_list[newRemoveAddressBox.targetAddress], x+9, y+1, name_list[newRemoveAddressBox.targetAddress]:len() - 10, 1, "none")
    table.insert(newRemoveAddressBox.content, tempObject)
    
    local tempObject = gui.createButton(gui, removeAddressBoxID .. "ConfirmButton", "REMOVE", newRemoveAddressBox.onRemove, x+1, y+2, 6, 1, "none")
    table.insert(newRemoveAddressBox.content, tempObject)
    
    local tempObject = gui.createButton(gui, removeAddressBoxID .. "CancelButton", "CANCEL", newRemoveAddressBox.onCancel, x+newRemoveAddressBox.w-7, y+2, 6, 1, "none")
    table.insert(newRemoveAddressBox.content, tempObject)

    return newRemoveAddressBox
end

local function addNewAddressButtonCallback(...)
    if address_locked then return false end
    local newAddressBox = addNewAddressBox.create(gui, "NewAddressBoxID", 1, 1)
    return popupWindow.create(gui, "NewAddressBoxPopupID", "thick", newAddressBox)
end

local function removeAddressButtonCallback(...)
    if address_locked then return false end
    local removeAddressBox = removeAddressBox.create(gui, "RemoveAddressBoxID", 1, 1)
    return popupWindow.create(gui, "RemoveAddressBoxPopupID", "thick", removeAddressBox)
end

local function dialButtonCallback(...)
    if address_locked then return false end
    local dialConfirmBox = confirmBox.create(
        gui, 
        nil,
        "DialConfirmBoxID",
        dialConfirmYes,
        nil,
        generalConfirmNo,
        nil,
        1,
        1,
        "Dial with",
        target_address
    )
    return popupWindow.create(gui, "DialConfirmBoxPopupID", "thick", dialConfirmBox)
end

local function closeConnectionButtonCallback(...)
    local closeConnectionConfirmBox = confirmBox.create(
        gui, 
        nil,
        "CloseConnectionConfirmBoxID",
        closeConnectionConfirmYes,
        nil,
        generalConfirmNo,
        nil,
        1,
        1,
        "Close Connection?"
    )
    return popupWindow.create(gui, "CloseConnectionConfirmBoxPopupID", "thick", closeConnectionConfirmBox)
end

function dialingInfoBox.create()
    local newDialingInfoBox = {}
    -- ╔╣CONNECTION╠╗
    -- ║    name    ║
    -- ║  address   ║
    -- ║  chevr*__  ║
    -- ║  █████▄__  ║
    -- ║ DISCONNECT ║
    -- ╚════════════╝

    newDialingInfoBox.type = "DialingInfoBox"
    newDialingInfoBox.ID = "DialingInfoBox"
    newDialingInfoBox.visible = true
    newDialingInfoBox.onClick = simpleContainerOnClick
    newDialingInfoBox.content = {}
    newDialingInfoBox.focused = false
    newDialingInfoBox.x = 1
    newDialingInfoBox.y = 1
    newDialingInfoBox.w = 14
    newDialingInfoBox.h = 5
    newDialingInfoBox.popupMaster = nil
    newDialingInfoBox.onDraw = drawObject
    newDialingInfoBox.chevronEventHandlerID = newDialingInfoBox.ID .. "ChevronEventHandler"

    newDialingInfoBox.onDelete = function(gui, self)
        gui:removeEventHandler(self.chevronEventHandlerID)
        return true
    end

    function newDialingInfoBox.onChevron(eventID, sourceStargateID, chevronNumber, symbol)
        gui:setSymbolInSymbolArray(newDialingInfoBox.content, newDialingInfoBox.ID .. "Chevrons", chevronNumber, 1, symbol)
        gui:setSymbolInSymbolArray(newDialingInfoBox.content, newDialingInfoBox.ID .. "Progress", chevronNumber, 1, gui.symbols.SYM_full_block)
        if chevronNumber < target_address:len() then
            gui:setSymbolInSymbolArray(newDialingInfoBox.content, newDialingInfoBox.ID .. "Chevrons", chevronNumber+1, 1, gui.symbols.SYM_caret)
            gui:setSymbolInSymbolArray(newDialingInfoBox.content, newDialingInfoBox.ID .. "Progress", chevronNumber+1, 1, gui.symbols.SYM_lower_block)
        end
        return true
    end
    
    local x, address_name = findNameByAddress(target_address)
    if address_name:len()   > newDialingInfoBox.w then newDialingInfoBox.w = address_name:len()     end
    if target_address:len() > newDialingInfoBox.w then newDialingInfoBox.w = target_address:len()   end

    -- content:
    -- name label
    local tempObject = gui:createLabel(newDialingInfoBox.ID .. "Name", address_name, math.floor(newDialingInfoBox.w-address_name:len())/2, 1, address_name:len(), 1, "none")
    table.insert(newDialingInfoBox.content, tempObject)
    -- address label
    local tempObject = gui:createLabel(newDialingInfoBox.ID .. "Address", target_address, math.floor(newDialingInfoBox.w-target_address:len())/2, 2, target_address:len(), 1, "none")
    table.insert(newDialingInfoBox.content, tempObject)
    -- chevrons custom field
    local tempObject = gui:createSymbolArray(newDialingInfoBox.ID .. "Chevrons", math.floor(newDialingInfoBox.w-target_address:len())/2, 3, target_address:len(), 1)
    table.insert(newDialingInfoBox.content, tempObject)
    -- progress custom field
    local tempObject = gui:createSymbolArray(newDialingInfoBox.ID .. "Progress", math.floor(newDialingInfoBox.w-target_address:len())/2, 4, target_address:len(), 1)
    table.insert(newDialingInfoBox.content, tempObject)
    -- disconnect button
    local tempObject = gui:createButton(newDialingInfoBox.ID .. "Disconnect", "DISCONNECT", closeConnectionButtonCallback, math.floor(newDialingInfoBox.w/2)-5, 5, 10, 1, "none")
    table.insert(newDialingInfoBox.content, tempObject)

    -- chevron and progress field init
    for i = 1, target_address:len(), 1 do
        gui:setSymbolInSymbolArray(newDialingInfoBox.content, newDialingInfoBox.ID .. "Chevrons", i, 1, "_")
        gui:setSymbolInSymbolArray(newDialingInfoBox.content, newDialingInfoBox.ID .. "Progress", i, 1, "_")
    end
    gui:setSymbolInSymbolArray(newDialingInfoBox.content, newDialingInfoBox.ID .. "Progress", 1, 1, gui.symbols.SYM_lower_block)

    gui:registerEventHandler(eventChevronEngaged, newDialingInfoBox.onChevron, newDialingInfoBox.chevronEventHandlerID)

    return newDialingInfoBox
end

-- on succesful beginning of dial
local function dialSuccessfullCallback(localStargateID, remoteStargateID)
    local newDialingInfoBox = dialingInfoBox.create()
    return popupWindow.create("dialingInfoBoxPopupID", "thick", newDialingInfoBox)
end

-- Event handler callbacks
local function sgDialInCallback(sourceStargateID, connectingStargateAddress)
    -- TODO: check if blacklist or whitelist are enabled and enforce them
    -- if blacklist/whitelist passed then
    address_locked = false
    setTargetAddress(connectingStargateAddress)
    address_locked = true
    return dialSuccessfullCallback(sourceStargateID, connectingStargateAddress)
    -- else
    -- disconnect
    -- return false
end

local function sgDialOutCallback(sourceStargateID, connectingStargateAddress)
    -- TODO: check if blacklist or whitelist are enabled and enforce them
    -- if blacklist/whitelist passed then
    return dialSuccessfullCallback(sourceStargateID, connectingStargateAddress)
    -- else
    -- disconnect
    -- return false
end

local function sgStargateStateChangeCallback(sourceStargateID, newState, oldState)
    if stargate_state_safety[newState] == true then
        if not stargate_door_locked then open_stargate_door() end
    else
        close_stargate_door()
    end
    if newState ~= "Idle" then address_locked = true else address_locked = false end
    if oldState == "Connected" then onDroppedConnection() end
    stargate_last_state = newState
    return true
end

local function sgIrisStateChangeCallback(sourceStargateID, newState, oldState)
    if newState == "Open" or newState == "Offline" then
        stargate_door_locked = false
        if stargate_state_safety[stargate_last_state] == true then
            open_stargate_door()
        end
    else
        stargate_door_locked = true
        close_stargate_door()
    end
    return true
end

local function sgMessageReceivedCallback(sourceStargateID, ...)
    local messageContent = {...}
    -- TODO: read the messages and act depending on the message
    -- likely will need to forward them to the local network
    return true
end

local function update_remote_address(remoteName, remoteAddress)
    -- check if the address is known and send our own address as a hello if it is new
    if address_list[remoteName] == nil then
        send_updated_address()
        return addNewAddress(gui, remoteName, remoteAddress)
    end

    if address_list[remoteName] == remoteAddress then return false end
    
    send_updated_address()
    address_list[remoteName] = remoteAddress
    return gui.changeItemInSelectList(gui, address_book_selectlist_id, remoteName, remoteName, setTargetAddress, remoteAddress)
end

local function lkMessageReceivedCallback(eventID, localAddress, remoteAddress, port, distance, serialized_data, ...)
    if localAddress ~= linked_card.address then return false end
    local data = serialization.unserialize(serialized_data)
    for name, address in pairs(data) do
        update_remote_address(name, address)
    end
    return true
end

local function loadConfig()
    local configTable, errMsg = kwlib.general.config.read(kwlib, CONFIG_FILE_PATH)
    if configTable == nil then
        io.write(errMsg)
        return false
    end

    LOCAL_NAME = configTable["localName"].value

    enable_blacklist = configTable["blacklist"].value
    enable_whitelist = configTable["whitelist"].value

    ADDRESS_UPDATE_TIMER_PERIOD = configTable["updateTimerPeriod"].value

    DATAFILE_SAVE_TIMER_PERIOD = configTable["saveDataFilePeriod"].value

    return true
end

local function sendCurrentStargateAddressThreadFunc()
    while running do
        if lastAddressUpdateTime + ADDRESS_UPDATE_TIMER_PERIOD < computer.uptime() then
            check_current_address()
            lastAddressUpdateTime = computer.uptime()
        end
        os.sleep(1)
    end
end

local function saveDataFileThreadFunc()
    while running do
        if lastDataSaveTime + DATAFILE_SAVE_TIMER_PERIOD < computer.uptime() or saveRequested then
            write_address_list()
            saveRequested = false
            lastDataSaveTime = computer.uptime()
        end
        os.sleep(1)
    end
end

-- init functions
local function initializeGUI()
    io.write("Loading config file... ")
    if loadConfig() then
        io.write("Success!\n")
    end

    -- say hello on the network
    send_updated_address()
    io.write("hello network!")

    print("Reading address book...")
    read_address_list()
    if #address_list > 1 then
        print("done")
    else
        print("address book not found or empty")
    end
    print(address_list)
    print("\n")
    print("creating GUI...")
    -- create a header
    local header_text = "STARGATE CONTROLS v" .. version_major .. "." .. version_minor
    gui.addObject(gui, "Label", header_id, header_text, math.floor((WIDTH-string.len(header_text))/2), 1, string.len(header_text), 1, "none")

    -- create and fill the list of addresses
    gui.addObject(gui, "SelectList", address_book_selectlist_id, 1, 2, WIDTH, HEIGHT-3, "thick")
    for name, address in pairs(address_list) do
        gui.addItemToSelectList(gui, address_book_selectlist_id, name, name, setTargetAddress, address)
    end

    -- create control buttons
    -- add new address
    gui.addObject(gui, "Button", "AddNewAddressButton", "ADD ADDRESS", addNewAddressButtonCallback, 2, HEIGHT-1, 11, 1, "none")
    -- dial selected
    gui.addObject(gui, "Button", "DialButton", "DIAL WITH SELECTED", dialButtonCallback, (WIDTH/2) - 9, HEIGHT-1, 18, 1, "none")
    -- remove selected address
    gui.addObject(gui, "Button", "RemoveAddressButton", "REMOVE ADDRESS", removeAddressButtonCallback, WIDTH - 15, HEIGHT-1, 14, 1, "none")
    -- send message
    -- ... TODO
    -- close connection
    gui.addObject(gui, "Button", "CloseConnectionButton", "CLOSE CONNECTION", closeConnectionButtonCallback, WIDTH - 17, HEIGHT, 16, 1, "none")

    -- create event listeners
    -- stargate events
    gui.registerEventHandler(gui, eventStargateDialInbound   , sgDialInCallback              )
    gui.registerEventHandler(gui, eventStargateDialOutbound  , sgDialOutCallback             )
    gui.registerEventHandler(gui, eventStargateStateChange   , sgStargateStateChangeCallback )
    gui.registerEventHandler(gui, eventIrisStateChange       , sgIrisStateChangeCallback     )
    gui.registerEventHandler(gui, eventMessageReceived       , sgMessageReceivedCallback     )

    -- linked card (and modem) messages
    gui.registerEventHandler(gui, "modem_message", lkMessageReceivedCallback)

    -- create savefile and address update threads
    stargateAddressUpdateThread = thread.create(sendCurrentStargateAddressThreadFunc)
    saveDataFileThread          = thread.create(saveDataFileThreadFunc)

    print("done")
    return true
end

-- finally, start of the script
print("Welcome to STARGATE Control v" .. version_major .. "." .. version_minor)
print("Initializing the system")
print("\n")
initializeGUI()
gui.run(gui)

-- tell the threads to stop and wait for them to quit
running = false
if stargateAddressUpdateThread ~= nil then 
    if not stargateAddressUpdateThread:join(5) then stargateAddressUpdateThread:kill() end
end
if saveDataFileThread ~= nil then
    if not saveDataFileThread:join(5) then saveDataFileThread:kill() end
end