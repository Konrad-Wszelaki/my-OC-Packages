local component     = require("component")
local serialization = require("serialization")
local io            = require("io")

local secureNetLib  = {}
secureNetLib.VERSION_MAJOR = "0"
secureNetLib.VERSION_MINOR = "1"

secureNetLib.initialized = false

function secureNetLib.version(self)
    return self.VERSION_MAJOR .. "." .. self.VERSION_MINOR
end
function secureNetLib.versionMajor(self)
    return self.VERSION_MAJOR
end
function secureNetLib.versionMinor(self)
    return self.VERSION_MINOR
end
function secureNetLib.checkVersionCompat(self, versionMajor, versionMinor)
    if versionMajor ~= self.VERSION_MAJOR then
        io.write("SecureNetLib major version mismatch, make sure the library version is compatible with this script!")
        return false
    end
    if tonumber(versionMinor) > tonumber(self.VERSION_MINOR) then
        io.write("SecureNetLib minor version older than required, make sure the library version is compatible with this script!")
        return false
    end
    return true
end

-- table of all known contacts and their cryptography information
secureNetLib.contactBook    = {}
-- table storing name-address pairs for convenient indexing of the contact book
-- e.g.: if contactBook has a contact with some UUID_1 and the contact's name is CONTACT_!, then DNSBook[CONTACT_!] == UUID_1
-- also contains the reverse of this pair, i.e.: DNSBook[UUID_1] == CONTACT_1
secureNetLib.DNSBook        = {}

-- table containing data loaded from the hard drive
secureNetLib.localData = {}
secureNetLib.localDataPath = "/usr/SecureNetData"
secureNetLib.localDataLoaded = false

-- definitions of prefixes used in the data file to store information about each contact
-- the prefix is directly followed by contact name in the data file (i.e.: __UNAME_CNAME1)
secureNetLib.prefixes = {}
secureNetLib.prefixes.REMOTE_ADDRESS_PREFIX     = "__RADDR_"
secureNetLib.prefixes.REMOTE_PORT_PREFIX        = "__RPORT_"
secureNetLib.prefixes.USERNAME_HASH_PREFIX      = "__UNAME_"
secureNetLib.prefixes.PASSWORD_HASH_PREFIX      = "__PSSWD_"
secureNetLib.prefixes.CLEARANCE_LEVEL_PREFIX    = "__CLLVL_"
secureNetLib.prefixes.BLACKLIST_STATUS_PREFIX   = "__BLIST_"

-- references to other libraries that need be initialized after importing the library
secureNetLib.KWLib = {}
-- version required by this script
secureNetLib.KWLibMajorVersion = "2"
secureNetLib.KWLibMinorVersion = "0"


-- references to the data card and the network card
-- the library assumes we have both, since both are needed for it to work
secureNetLib.dataCard       = component.data
secureNetLib.networkCard    = component.modem

-- CONSTANTS --
-- key length to use in comms
secureNetLib.KEY_LENGTH = 384
-- name of the local computer to be used in the network. Must be initialized before using the library
secureNetLib.COMPUTER_NAME = nil

-- list of trust levels for information-sharing decisions
-- the strings are only for writing to the screen of the UI, changing them will not break anything
-- you can modify it in runtime to define your own clearance/restriction levels or change their descriptions, as it is only used locally
secureNetLib.trustLevels = {
    [0]  = "full_access",
    [1]  = "clearance_lvl_1",
    [2]  = "clearance_lvl_2",
    [3]  = "clearance_lvl_3",
    [4]  = "clearance_lvl_4",
    [-1] = "no_access"
}

-- list of possible states that the given contact can be in
-- the strings are only for writing to the screen of the UI, changing them will not break anything
-- you can extend it for your own needs and change the descriptions of the existing states, but do not remove the default ones
secureNetLib.contactStates = {
    [-1] = "blacklisted"
    [0]  = "disconnected"
    [1]  = "handshake_request_sent"
    [2]  = "connected"
    [3]  = "keys_expired"
}

-- list of types of packets that can always be expected to be used
-- the strings are only for writing to the screen of the UI, changing them will not break anything
-- you can extend it for your own needs and change the descriptions of the existing types, but do not remove the default ones
secureNetLib.packetTypes = {
    [0]  = "handshake_request"
    [1]  = "ACK"  -- also handshake affirm
    [-1] = "NACK" -- also handshake deny
    [2]  = "key_renewal"
    [-2] = "drop_connection"
    [3]  = "clearance_request"
}

-- saving and loading data files
-- data structure:
-- {
--      [contact1_name] -> {
--          [address_prefix..contact1_name]  -> address
--          [port_prefix..contact1_name]     -> port
--          ...
--      }
--      [contact2_name] -> {
--          [address_prefix..contact2_name]  -> address
--          [port_prefix..contact2_name]     -> port
--          ...
--      }
--      ...
-- }
--
-- e.g.:  data[some_contact_name][REMOTE_ADDRESS_PREFIX .. some_contact_name] will give the address of the computer with that name
--
-- the data files are not supposed to be written by a person though, so this is mostly for information on how things work around here
function secureNetLib.readDataFile(self)
    local data, errMsg = self.KWLib.general.dataFiles.readDataFile(self.KWLib, self.localDataPath, self.dataCard)
    if data == nil then
        io.write("SecureNet Data File loading failed with error: " .. errMsg .. "\n")
        return false, errMsg
    end
    self.localData = data
    self.localDataLoaded = true
    return true
end
function secureNetLib.writeDataFile(self)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    return self.KWLib.general.dataFiles.saveDataFile(self.KWLib, self.localDataPath, self.localData, self.dataCard)
end

function secureNetLib.addDatumToLocalData(self, contactName)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    -- check if the contact exists
    if not type(self.DNSBook[contactName]) == "string" then return false end

    -- fill the data
    local newDatum = {}
    newDatum[REMOTE_ADDRESS_PREFIX      .. contactName] = self.DNSBook[contactName].
    newDatum[REMOTE_PORT_PREFIX         .. contactName] = self.contactBook[self.DNSBook[contactName]].port
    newDatum[USERNAME_HASH_PREFIX       .. contactName] = self.contactBook[self.DNSBook[contactName]].credentials.username_md5
    newDatum[PASSWORD_HASH_PREFIX       .. contactName] = self.contactBook[self.DNSBook[contactName]].credentials.password_md5
    newDatum[CLEARANCE_LEVEL_PREFIX     .. contactName] = self.contactBook[self.DNSBook[contactName]].loggedInTrustLevel
    newDatum[BLACKLIST_STATUS_PREFIX    .. contactName] = (self.contactBook[self.DNSBook[contactName]].contactState == -1)

    -- add to table
    self.localData[contactName] = newDatum
    return true
end

-- initialize contact book from loaded data
function secureNetLib.initializeContactBook(self)
    if not self.localDataLoaded then return false end
    for key, index in pairs(self.localData) do
        local newContact = self.getContactTemplate()
        -- initialize the contact info
        newContact.address  = self.localData[key][self.prefixes.REMOTE_ADDRESS_PREFIX   .. key]
        newContact.port     = self.localData[key][self.prefixes.REMOTE_PORT_PREFIX      .. key]

        -- pregenerate the key pair
        newContact.localKeyPair.public, newContact.localKeyPair.private = self.dataCard.generateKeyPair(self.KEY_LENGTH)

        -- initialize credentials and set state to 'blacklisted' if the data says that we don't like this contact
        newContact.loggedInTrustLevel       = self.localData[key][self.prefixes.CLEARANCE_LEVEL_PREFIX  .. key]
        newContact.credentials.username_md5 = self.localData[key][self.prefixes.USERNAME_HASH_PREFIX    .. key]
        newContact.credentials.password_md5 = self.localData[key][self.prefixes.PASSWORD_HASH_PREFIX    .. key]
        if self.localData[key][self.prefixes.BLACKLIST_STATUS_PREFIX .. key] then
            newContact.contactState = -1
        end

        -- add contact to contact book
        self.contactBook[newContact.address] = newContact
        -- and to the 'DNS' book
        self.DNSBook[key] = newContact.address
        -- also add the UUID->name pair for convenience
        self.DNSBook[newContact.address] = key
    end
    return true
end

-- contact template
function secureNetLib.getContactTemplate()
    local contactTemplate = {}

    contactTemplate.port            = nil
    contactTemplate.remotePublicKey = nil
    contactTemplate.iV              = nil

    contactTemplate.localKeyPair = {}
    contactTemplate.localKeyPair.private = nil
    contactTemplate.localKeyPair.public  = nil
    contactTemplate.ecdh = nil

    contactTemplate.trustLevel          = -1
    contactTemplate.loggedInTrustLevel  = -1
    contactTemplate.credentials  = {}
    contactTemplate.credentials.username_md5 = nil
    contactTemplate.credentials.password_md5 = nil
    contactTemplate.contactState = 0

    return contactTemplate
end

function secureNetLib.addNewContact(self, contactName, contactAddress, contactPort, contactPublicKey, contactIV)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    local newContact = self.getContactTemplate()

    newContact.port             = contactPort
    newContact.remotePublicKey  = contactPublicKey
    newContact.iV               = contactIV
    if newContact.iV == nil then
        newContact.iV = self.dataCard.random(16)
    end

    newContact.localKeyPair.public, newContact.localKeyPair.private = self.dataCard.generateKeyPair(self.KEY_LENGTH)
    if not newContact.remotePublicKey == nil then
        newContact.ecdh = self.dataCard.md5(self.dataCard.ecdh(newContact.localKeyPair.private, newContact.remotePublicKey))
        newContact.contactState = 2
    end

    -- add to the books
    self.contactBook[contactAddress] = newContact
    self.DNSBook[contactName] = contactAddress
    self.DNSBook[contactAddress] = contactName

    -- add to the local data
    self.addDatumToLocalData(self, contactName)

    return true
end

-- will remove the contact from contactBook and from local data
function secureNetLib.removeContact(self, contactName)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    -- remove the contact
    self.contactBook[self.DNSBook[contactName]] = nil
    -- remove the UUID->name pair
    self.DNSBook[self.DNSBook[contactName]] = nil
    -- remove the name->UUID pair
    self.DNSBook[contactName] = nil

    -- remove from savefile data
    table.remove(self.localData, contactName)
    return true
end

-- packet template
function secureNetLib.getPacketTemplate()
    local packet = {}
    
    -- header contains the packet type ID, serialized private key string and the initialization vector
    packet.header = {}
    packet.header.type = nil
    packet.header.pK   = nil
    packet.header.iV   = nil

    -- body contains the serialzied data
    packet.body = {}
    packet.body.data  = nil

    -- footer contains an md5 hash of the serialized data
    packet.footer = {}
    packet.footer.md5 = nil

    return packet
end

-- function that will serialize and encode the data table before you send it to a given contact
function secureNetLib.encodeDataTable(self, contactName, data)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    -- check if contact is known
    if self.contactBook[self.DNSBook[contactName]] == nil then
        io.write("Contact \"" .. contactName .. "\" not found, data cannot be encrypted!\n")
        return false
    end
    -- check if encryption/decryptiuon key was computer already, and do so if not
    if self.contactBook[self.DNSBook[contactName]].ecdh == nil then
        self.contactBook[self.DNSBook[contactName]].ecdh = self.dataCard.md5(self.dataCard.ecdh(self.contactBook[self.DNSBook[contactName]].localKeyPair.private, self.contactBook[self.DNSBook[contactName]].remotePublicKey))
    end
    
    -- encrypt and return the data
    return self.dataCard.encrypt(serialization.serialize(data), self.contactBook[self.DNSBook[contactName]].ecdh, self.contactBook[self.DNSBook[contactName]].iV)
end

-- function that will decode and deserialize data received from the given contact
function secureNetLib.decodeDataTable(self, contactName, data)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    -- check if contact is known
    if self.contactBook[self.DNSBook[contactName]] == nil then
        io.write("Contact \"" .. contactName .. "\" not found, data cannot be decrypted!\n")
        return false
    end
    -- check if encryption/decryptiuon key was computer already, and do so if not
    if self.contactBook[self.DNSBook[contactName]].ecdh == nil then
        self.contactBook[self.DNSBook[contactName]].ecdh = self.dataCard.md5(self.dataCard.ecdh(self.contactBook[self.DNSBook[contactName]].localKeyPair.private, self.contactBook[self.DNSBook[contactName]].remotePublicKey))
    end

    -- decrypt and return the deserialized data
    return serialization.unserialize(self.dataCard.decrypt(data, self.contactBook[self.DNSBook[contactName]].ecdh, self.contactBook[self.DNSBook[contactName]].iV))
end

function secureNetLib.getNACKPacket(self)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    local NACK = self.getPacketTemplate()
    NACK.header.type = -1
    return NACK
end

function secureNetLib.getACKPacket(self, contactName)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    local ACK = self.getPacketTemplate()
    ACK.header.type = 1
    ACK.header.pK = self.contactBook[self.DNSBook[contactName]].localKeyPair.public.serialize()
    ACK.header.iV = self.contactBook[self.DNSBook[contactName]].iV
    return ACK
end

function secureNetLib.getHandshakePacket(self, contactName)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    local HANDSHAKE = self.getPacketTemplate()

    HANDSHAKE.header.type   = 0
    HANDSHAKE.header.pK     = self.contactBook[self.DNSBook[contactName]].localKeyPair.public
    self.contactBook[self.DNSBook[contactName]].iV = self.dataCard.random(16)
    HANDSHAKE.header.iV  = self.contactBook[self.DNSBook[contactName]].iV

    HANDSHAKE.body.data  = self.COMPUTER_NAME
    HANDSHAKE.footer.md5 = self.dataCard.md5(self.COMPUTER_NAME)

    return HANDSHAKE
end

-- handshake procedure:
-- 1) handshake request is received with type = 0, pK and iV filled and contact name in data
-- 2) blacklist is checked to verify remoteAddress is not blocked. NACK is sent if it is blocked
-- 3) if the contact is not known, create a new one and add it to the book. If the contact is known, check if the address and name match up to avoid spoofing. send NACK if addresses are different, update the contact otherwise.
-- 4) ACK is sent with local name as data
function secureNetLib.onHandshakeRequest(self, remoteAddress, port, deserializedPacket, localName)
    if not self.initialized then
        io.write("OCSecureNetLib not initialized!\n")
        return false
    end
    
    
end


function secureNetLib.initializeLibrary(self, KWLib, localComputerName)
    io.write("OCSecureNetLib checking KWLib version compatibility: ")
    if not KWLib.checkVersionCompat(KWLib, self.KWLibMajorVersion, self.KWLibMinorVersion) then return false end
    io.write("KWLib compatible\n")
    self.KWLib = KWLib

    io.write("OCSecureNetLib attempting to load a data file: ")
    if self.readDataFile(self) then
        io.write("success!\n")
        io.write("intitializing the contact book... ")
        if self.initializeContactBook(self) then io.write("success!\n") else io.write("initialization failed\n") end
    end

    if type(localComputerName) ~= "string" then
        io.write("Computer name not specified, cannot proceed...\n")
        return false
    end
    self.COMPUTER_NAME = localComputerName
    io.write("OCSecureNet local name set to : " .. self.COMPUTER_NAME .. "\n")

    
    secureNetLib.initialized = true
    io.write("SecureNetLib initialized successfully!\n")
    return true
end
return secureNetLib