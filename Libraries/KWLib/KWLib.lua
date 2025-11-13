local io            = require("io")
local text          = require("text")
local sides         = require("sides")
local serialization = require("serialization")

local KWLIB = {}

-- !!! on every function call, the first argument should be the library itself !!!
-- e.g.: local kwlib = require("KWLib") [...] kwlib.general.createCircularBuffer(kwlib, 20)
-- do not use kwlib.general:createCircularBuffer(...), because then kwlib.general will be put into self instead of kwlib itself

KWLIB.VERSION_MAJOR = "2"
KWLIB.VERSION_MINOR = "2"

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

-- handling of data files
-- file format consists of key-data pairs
-- keys are strings that act as indices in the loaded data table
-- data is serialized and compressed, so it is also a string in the file
-- thanks to this, the actual data can be anything from simple integers to large tables
-- each line contains one key-data pair, with a cofigurable value separator between them (default: ';')
KWLIB.general.dataFiles = {}
-- constants
KWLIB.general.dataFiles.FILE_EXTENSION  = ".dat"
KWLIB.general.dataFiles.VALUE_SEPARATOR = ";"

-- saving data files
-- if a reference to a dataCard is not given as an argument, the data will not be compressed
function KWLIB.general.dataFiles.saveDataFile(self, path, dataArray, dataCard)
    local dataFile, errMsg = io.open(path .. self.general.dataFiles.FILE_EXTENSION, "w")
    if (dataFile == nil) then return false, errMsg end

    for key, data in pairs(dataArray) do
        data = serialization.serialize(data)
        if type(dataCard) == "table" then
            data = dataCard.deflate(data)
        end
        local a, b = dataFile:write(key .. self.general.dataFiles.VALUE_SEPARATOR .. data .. self.general.dataFiles.VALUE_SEPARATOR .. "\n")
        if (a == nil) then
            return false, b
        end
    end

    return true
end

-- reading data files
-- if a reference to a dataCard is not given as an argument, the data is assumed to not be compressed
-- if a reference to a dataCard is given as an argument, the data is assumed to be compressed
function KWLIB.general.dataFiles.readDataFile(self, path, dataCard)
    local dataFile, errMsg = io.open(path .. self.general.dataFiles.FILE_EXTENSION)
    if dataFile == nil then return false, errMsg end

    local dataArray = {}
    for line in dataFile:lines() do
        -- split and clean-up the key and data
        local substrings = self.strings.splitString(self, line, self.general.dataFiles.VALUE_SEPARATOR)
        for index in ipairs(substrings) do
            substrings[index] = string.gsub(substrings[index], self.general.dataFiles.VALUE_SEPARATOR, " ")
            substrings[index] = text.trim(substrings[index])
        end
        -- add data to table
        if type(dataCard) == "table" then
            dataArray[substrings[1]] = serialization.unserialize(dataCard.inflate(substrings[2]))
        else
            dataArray[substrings[1]] = serialization.unserialize(substrings[2])
        end
    end

    return dataArray
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
        if content == object then return true, index end
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

-- function to split a given string to multiple strings with a given maximum width
-- will only move complete words
-- gives up if a word is too long for the given width (TODO: handle this in a better way)
function KWLIB.strings.splitStringIntoLines(self, stringToSplit, maxWidth)
    local substrings = {}
    if stringToSplit:len() <= maxWidth then
        table.insert(substrings, stringToSplit)
        return substrings
    end
    local index = maxWidth
    local lastIndex = 1
    while index <= string.len(stringToSplit)  do
        while stringToSplit:sub(index, index) ~= " " do
            index = index - 1
            if index == lastIndex then
                index = index + maxWidth
                break
            end
        end
        table.insert(substrings, stringToSplit:sub(lastIndex, index-1))
        lastIndex = index + 1
        index = index + maxWidth
    end

    if index > stringToSplit:len() and lastIndex <= stringToSplit:len() then table.insert(substrings, stringToSplit:sub(lastIndex, stringToSplit:len())) end

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

------------------------------------------------------------------------------------------------
-- tables
KWLIB.tables = {}

function KWLIB.tables.countEntries(self, array)
    if type(array) ~= "table" then return false end
    local count = 0
    for a, b in pairs(array) do
        if b ~= nil then count = count + 1 end
    end
    return count
end

------------------------------------------------------------------------------------------------
-- colors

KWLIB.colors = {}

-- input: values of R G B color in range 0-255
function KWLIB.colors.RGBToHex(self, R, G, B)
    if R < 0 or G < 0 or B < 0 or R > 255 or G > 255 or B > 255 then return false end
    if math.type(R) ~= "integer" or math.type(G) ~= "integer" or math.type(B) ~= "integer" then return false end

    R = string.format("%x", R)
    G = string.format("%x", G)
    B = string.format("%x", B)

    if string.len(R) == 1 then R = "0"..R end
    if string.len(G) == 1 then G = "0"..G end
    if string.len(B) == 1 then B = "0"..B end

    return R..G..B
end

-- input: color string in format 0xRRGGBB
function KWLIB.colors.HexToRGB(self, hexColor)
    hexColor = "0x"..string.format("%x", hexColor)
    if string.len(hexColor) ~= 8 then return false end
    local R = tonumber(string.sub(hexColor, 3, 4), 16)
    local G = tonumber(string.sub(hexColor, 5, 6), 16)
    local B = tonumber(string.sub(hexColor, 7, 8), 16)
    return R, G, B
end

function KWLIB.colors.scaleColor(self, hexColor, scaleFactor)
    local R, G, B = self.colors.HexToRGB(self, hexColor)
    if R == false then return false end
    R, G, B = math.floor(R*scaleFactor), math.floor(G*scaleFactor), math.floor(B*scaleFactor)
    if R < 0 then R = 0 end
    if R > 255 then R = 255 end

    if G < 0 then G = 0 end
    if G > 255 then G = 255 end

    if B < 0 then B = 0 end
    if B > 255 then B = 255 end

    return tonumber(self.colors.RGBToHex(self, R, G, B), 16)
end

function KWLIB.colors.sumColors(self, hexColor1, hexColor2)
    local R1, G1, B1 = self.colors.HexToRGB(hexColor1)
    local R2, G2, B2 = self.colors.HexToRGB(hexColor2)
    if R1 == false or R2 == false then return false end
    local R, G, B = R1+R2, G1+G2, B1+B2
    
    if R < 0 then R = 0 end
    if R > 255 then R = 255 end

    if G < 0 then G = 0 end
    if G > 255 then G = 255 end

    if B < 0 then B = 0 end
    if B > 255 then B = 255 end

    return tonumber(self.colors.RGBToHex(self, R, G, B), 16)
end

return KWLIB