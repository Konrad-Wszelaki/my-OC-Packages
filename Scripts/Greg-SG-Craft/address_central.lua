local version_major = "1"
local version_minor = "0"

local component     = require("component")
local serialization = require("serialization")
local event         = require("event")

local network_card = component.modem
local paired_card  = component.tunnel

local NETWORK_COMMS_PORT = 13
network_card.open(NETWORK_COMMS_PORT)

local run = true

local function handleLocalNetworkMessage(localAddress, remoteAddress, port, distance, serializedPacket, ...)
    if type(serializedPacket) ~= "string" or port ~= NETWORK_COMMS_PORT then return false end
    --local data = serialization.unserialize(serializedPacket)
    --print("Local message: ")
    --print(data)
    for key, datum in pairs(data) do
        --print(key .. " - " .. datum)
        if type(key) ~= "string" or type(datum) ~= "string" then return false end
    end
    --print("\n")
    paired_card.send(serializedPacket)
end

local function handlePairedCardMessage(localAddress, remoteAddress, port, distance, serializedPacket, ...)
    if type(serializedPacket) ~= "string" then return false end
    --local data = serialization.unserialize(serializedPacket)
    --print("Paired Card message: ")
    --print(data)
    for key, datum in pairs(data) do
        --print(key .. " - " .. datum)
        if type(key) ~= "string" or type(datum) ~= "string" then return false end
    end
    --print("\n")
    network_card.broadcast(NETWORK_COMMS_PORT, serializedPacket)
end

local function handleEvent(eventID, ...)
    local args = {...}
    if eventID == "modem_message" then
        if args[1] == paired_card.address then
            return handlePairedCardMessage(...)
        else
            return handleLocalNetworkMessage(...)
        end
    end
    if eventID == "interrupted" then
        run = false
        return true
    end
    return false
end

local function runLoop()
    while run==true do
        handleEvent(event.pull())
    end
end

-- run the script
--print("starting the script!")
runLoop()
--print("closing the script!")

