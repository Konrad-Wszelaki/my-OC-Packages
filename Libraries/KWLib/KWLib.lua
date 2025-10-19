local io            = require("io")
local text          = require("text")
local sides         = require("sides")
local serialization = require("serialization")
local filesystem    = require("filesystem")
local shell         = require("shell")
local computer      = require("computer")

local KWLIB = {}

-- !!! on every function call, the first argument should be the library itself !!!
-- e.g.: local kwlib = require("KWLib") [...] kwlib.general.createCircularBuffer(kwlib, 20)
-- do not use kwlib.general:createCircularBuffer(...), because then kwlib.general will be put into self instead of kwlib itself

KWLIB.VERSION_MAJOR = "2"
KWLIB.VERSION_MINOR = "3"

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

-- Update All Packages
-- A function that will call OPPM Update when available and, optionally, restart the computer
function KWLIB.general.updateAllPackages(self, restart)
    local success, failMsg = shell.execute("OPPM update all")
    if success and restart then computer.shutdown(true) end
    return success, failMsg
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

-- simple mapping from a string to boolean
KWLIB.strings.toBoolean = {["true"]=true, ["false"]=false}

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
-- Items
KWLIB.items = {}

-- function to consolidate all the stacks in the input array to single entries that may exceed max stack size of each item
-- some information is lost (damage values for tools etc.)
-- return array is indexed by item name (the display name)
function KWLIB.items.consolidateStackList(self, inputArray)
    if type(inputArray) ~= "table" then return false end
    local outputArray = {}
    for index, itemStack in pairs(inputArray) do
        if type(itemStack) == "table" and itemStack.label ~= nil then
            if outputArray[itemStack.label] == nil then
                outputArray[itemStack.label] = {}
                outputArray[itemStack.label].size    = itemStack.size
                outputArray[itemStack.label].maxSize = itemStack.maxSize
                outputArray[itemStack.label].id      = itemStack.id
                outputArray[itemStack.label].name    = itemStack.name
                outputArray[itemStack.label].label   = itemStack.label
            else
                outputArray[itemStack.label].size    = outputArray[itemStack.label].size + itemStack.size
            end
        end
    end
    return outputArray
end

-- function that checks if the given inventory contains enough items to satisfy the requiredItems list
-- will consolidate both lists before checking the condition, unless skipConsolidation is set to true
function KWLIB.items.checkIfInventoryContainsListedItems(self, inventory, requiredItems, skipConsolidation)
    if not skipConsolidation then
        inventory       = self.items.consolidateStackList(self, inventory)
        requiredItems   = self.items.consolidateStackList(self, requiredItems)
    end
    if type(inventory) ~= "table" or type(requiredItems) ~= "table" then return false end

    for item, itemData in pairs(requiredItems) do
        if type(inventory[item])~="table" or inventory[item].size < itemData.size then return false end
    end
    return true
end

------------------------------------------------------------------------------------------------
-- Recipes
KWLIB.recipes = {}

--constants
KWLIB.recipes.FILE_EXTENSION = ".rcp"
KWLIB.recipes.LINE_VALUE_SEPARATOR = ";"

-- reads a recipe from file
-- path argument should be provided with no file extension
-- recipe is formatted as an integer-indexed table, with each index corresponding to the slot in the crafting interface that needs be filled with a given item
-- recipe files are formatted as such:
-- 0; output Item Name; output Item Display Name; output Count; output Max Stack; output Damage
-- 1; input Item Name slot 1; input Item Display Name slot 1; input Count slot 1; input Max Stack slot 1; input damage slot 1; not consumable slot 1
-- 2; input Item Name slot 2; input Item Display Name slot 2; input Count slot 2; input Max Stack slot 2; input damage slot 2; not consumable slot 2
-- ...
--
-- items do not need to be in order and indices can be skipped for recipes that require it
-- returns false if any line is defined improperly
function KWLIB.recipes.readRecipeFromFile(self, recipeFilePath)
    if not filesystem.exists(recipeFilePath..self.recipes.FILE_EXTENSION) then return false end
    local recipe = {}
    recipe.input = {}
    local recipeFile = io.open(recipeFilePath..self.recipes.FILE_EXTENSION)
    for line in recipeFile:lines() do
        local lineValues = self.strings.splitString(self, line, self.recipes.LINE_VALUE_SEPARATOR)
        for index in ipairs(lineValues) do
            lineValues[index] = string.gsub(lineValues[index], self.recipes.LINE_VALUE_SEPARATOR, " ")
            lineValues[index] = text.trim(lineValues[index])
        end
        if tonumber(lineValues[1]) == 0 and #lineValues == 6 then
            recipe.output = {}
            recipe.output.name      = text.trim(lineValues[2])
            recipe.output.label     = text.trim(lineValues[3])
            recipe.output.size      = tonumber(text.trim(lineValues[4]))
            recipe.output.maxSize   = tonumber(text.trim(lineValues[5]))
            recipe.output.damage    = tonumber(text.trim(lineValues[6]))
        else
            if #lineValues == 7 then
                local index = tonumber(lineValues[1])
                recipe.input[index] = {}
                recipe.input[index].name          = text.trim(lineValues[2])
                recipe.input[index].label         = text.trim(lineValues[3])
                recipe.input[index].size          = tonumber(text.trim(lineValues[4]))
                recipe.input[index].maxSize       = tonumber(text.trim(lineValues[5]))
                recipe.input[index].damage        = tonumber(text.trim(lineValues[6]))
                recipe.input[index].nonConsumable = self.strings.toBoolean[text.trim(lineValues[7])]
            else
                return false
            end
        end
    end
    recipeFile:close()
    return recipe
end

return KWLIB