local io            = require("io")
local text          = require("text")
local sides         = require("sides")
local serialization = require("serialization")

local KWLIB = {}

-- !!! on every function call, the first argument should be the library itself !!!
-- e.g.: local kwlib = require("KWLib") [...] kwlib.general.createCircularBuffer(kwlib, 20)
-- do not use kwlib.general:createCircularBuffer(...), because then kwlib.general will be put into self instead of kwlib itself

KWLIB.VERSION_MAJOR = "2"
KWLIB.VERSION_MINOR = "0"

function KWLIB.version(self)
    return self.VERSION_MAJOR .. "." .. self.VERSION_MINOR
end
function KWLIB.versionMajor(self)
    return self.VERSION_MAJOR
end
function KWLIB.versionMinor(self)
    return self.VERSION_MINOR
end
function KWLIB.checkVersionCompat(self, versionMajor, versionMinor)
    if versionMajor ~= self.VERSION_MAJOR then
        io.write("KWLIB major version mismatch, make sure the library version is compatible with this script!")
        return false
    end
    if tonumber(versionMinor) > tonumber(self.VERSION_MINOR) then
        io.write("KWLIB minor version older than required, make sure the library version is compatible with this script!")
        return false
    end
    return true
end
------------------------------------------------------------------------------------------------
-- general functionality
KWLIB.general = {}


-- Circular Buffer
-- it's a constant-size storage that overwrites the oldest data once the size limit is reached
-- the function to return stored data gives it in chronological order
function KWLIB.general.createCircularBuffer(self, size)
    local newCircularBuffer = {}

    newCircularBuffer.size = size
    newCircularBuffer.data = {}
    newCircularBuffer.oldestDataIndex = 0

    newCircularBuffer.addDatum = function (datum)
        if #newCircularBuffer.data < newCircularBuffer.size then
            newCircularBuffer.data[#newCircularBuffer.data + 1] = datum
            if newCircularBuffer.oldestDataIndex == 0 then newCircularBuffer.oldestDataIndex = 1 end
        else
            newCircularBuffer.data[newCircularBuffer.oldestDataIndex] = datum
            newCircularBuffer.oldestDataIndex = newCircularBuffer.oldestDataIndex + 1
            if newCircularBuffer.oldestDataIndex > newCircularBuffer.size then newCircularBuffer.oldestDataIndex = 1 end
        end
    end

    newCircularBuffer.getData = function ()
        local data_chronological = {}
        for i = 1, #newCircularBuffer.data do
            if (i+newCircularBuffer.oldestDataIndex-1) <= newCircularBuffer.size then
                data_chronological[i] = newCircularBuffer.data[i + newCircularBuffer.oldestDataIndex - 1]
            else
                data_chronological[i] = newCircularBuffer.data[i + newCircularBuffer.oldestDataIndex - (1 + newCircularBuffer.size)]
            end
        end
        return data_chronological
    end

    return newCircularBuffer
end

-- handling of configuration files
-- config file row has the following format:
--    variable : value : type : comment :
-- with any number of spaces/tabs next to the separators
-- the fourth ':' at the end of the line is important. Anything written after it will be ignored and will not persist when saving the config file
KWLIB.general.config = {}
-- config file constants
KWLIB.general.config.FILE_EXTENSION = ".cfg"
KWLIB.general.config.VALUE_SEPARATOR = ":"

-- writing config files
function KWLIB.general.config.write(self, configArray, configFilePath)
    local configFile, errMsg = io.open(configFilePath .. self.general.config.FILE_EXTENSION, "w")
    if (configFile == nil) then
        return false, errMsg
    end

    for name, content in pairs(configArray) do
        local a, b = configFile:write(name..self.general.config.VALUE_SEPARATOR..tostring(content.value)..self.general.config.VALUE_SEPARATOR..type(content.value)..self.general.config.VALUE_SEPARATOR..content.comment..self.general.config.VALUE_SEPARATOR.."\n")
        if (a == nil) then
            return false, b
        end
    end

    return true
end

-- reading config files
function KWLIB.general.config.read(self, configFilePath)
    local configArray = {}

    local configFile, errMsg = io.open(configFilePath .. self.general.config.FILE_EXTENSION)
    if (configFile == nil) then
        return nil, errMsg
    end

    for line in configFile:lines() do
        local substrings = self.strings.splitString(self, line, self.general.config.VALUE_SEPARATOR)
        for index in ipairs(substrings) do
            substrings[index] = string.gsub(substrings[index], self.general.config.VALUE_SEPARATOR, " ")
            substrings[index] = text.trim(substrings[index])
        end
        configArray[substrings[1]] = {}
        substrings[3]:lower()
        if (substrings[3] == "boolean") then
            configArray[substrings[1]].value = (substrings[2]:lower() == "true")
        elseif (substrings[3] == "number") then
            configArray[substrings[1]].value = tonumber(substrings[2])
        else
            configArray[substrings[1]].value = substrings[2]
        end
        configArray[substrings[1]].comment = substrings[4]
    end

    return configArray
end

-- a simple function that maps the input from one range of values to another
-- the value must be a number and ranges must be tables of two numbers indicating the beginning and the end of the range
-- TODO: move to mathematical
function KWLIB.general.map(self, value, fromRange, toRange)
    return (((value - fromRange[1])/(fromRange[2]-fromRange[1])) * (toRange[2]-toRange[1])) + toRange[1]
end

-- PID controls
KWLIB.general.PID = {}

function KWLIB.general.PID.createPIDInstance(self, kP, kI, kD)
    local PID = {}

    PID.kP = kP
    PID.kI = kI
    PID.kD = kD

    function PID.calculateControlValue(self, eP, eI, eD)
        return eP * self.kP + eI * self.kI + eD * self.kD
    end

    return PID
end

function KWLIB.general.lookForOccurenceInTable(table, object)
    for index, content in pairs(table) do
        if content == object then return true end
    end
    return false
end

------------------------------------------------------------------------------------------------
-- strings
KWLIB.strings = {}


-- function to split a given string to substrings using a given delimiter
function KWLIB.strings.splitString(self, stringToSplit, delimiter)
    local substrings = {}
    for substring in stringToSplit:gmatch("[^"..delimiter.."]*"..delimiter) do
        table.insert(substrings, substring)
    end
    return substrings
end

------------------------------------------------------------------------------------------------
-- directional
KWLIB.directional = {}


function KWLIB.directional.getOppositeDirection(self, direction)
    if direction == sides.north then return sides.south end
    if direction == sides.east  then return sides.west  end
    if direction == sides.south then return sides.north end
    if direction == sides.west  then return sides.east  end
    if direction == sides.up    then return sides.down  end
    if direction == sides.down  then return sides.up    end
end

------------------------------------------------------------------------------------------------
-- mathematical
KWLIB.mathematical = {}


function KWLIB.mathematical.getMaxValue(self, valuesArray)
    local max = 0
    for index, value in ipairs(valuesArray) do
        if value > max then max = value end
    end
    return max
end

function KWLIB.mathematical.getMinValue(self, valuesArray)
    local min = nil
    for index, value in ipairs(valuesArray) do
        if min == nil then min = value end
        if value < min then min = value end
    end
    return min
end

function KWLIB.mathematical.getAverageValue(self, valuesArray)
    local sum = 0
    local n   = 0
    for index, value in ipairs(valuesArray) do
        sum = sum + value
        n   = n   + 1
    end
    return avg / n
end

function KWLIB.mathematical.getDifferenceFromAverage(self, valuesArray)
    local average = self.mathematical.getAverageValue(self, valuesArray)
    local results = {}
    for index, value in ipairs(valuesArray) do
        results[index] = average - value
    end
    return results
end

function KWLIB.mathematical.getDifferenceFromValue(self, valuesArray, comparisonValue)
    local results = {}
    for index, value in ipairs(valuesArray) do
        results[index] = value - comparisonValue
    end
    return results
end

function KWLIB.mathematical.getSlope(self, timeValuePairsArray)
    local deltaT = 0.0
    local deltaV = 0.0
    local n = 0
    for time, value in ipairs(timeValuePairsArray) do
        deltaV = deltaV + value
        deltaT = deltaT + time
        n = n + 1
    end
    deltaV = deltaV / n
    deltaT = deltaT / n
    local numerator     = 0.0
    local denominator   = 0.0
    for time, value in ipairs(timeValuePairsArray) do
        numerator   = numerator   + ((time-deltaT) * (value-deltaV))
        denominator = denominator + ((time-deltaT) * (time -deltaT))
    end
    return numerator/denominator
end

------------------------------------------------------------------------------------------------
-- networking
KWLIB.networking = {}
-- must add modem as an argument to all functions to make the library not require a network card for functions that do not require it

function KWLIB.networking.sendOneMessageToMultipleAddresses(self, modem, addressTable, portTable, ...)
    if type(addressTable) ~= "table" or type(portTable) ~= "table" or #addressTable ~= #portTable then
        return false
    end
    for i=1, #addressTable, 1 do
        modem.send(addressTable[i], portTable[i], ...)
    end
    return true
end

return KWLIB