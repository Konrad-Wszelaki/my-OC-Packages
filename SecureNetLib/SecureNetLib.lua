local secureNetLib  = {}
local component     = require("component")
local serialization = require("serialization")
local io            = require("io")

-- table of all known contacts and their cryptography information
secureNetLib.contactBook = {}

-- references to other libraries that need be initialized after importing the library
secureNetLib.KWLib = {}
secureNetLib.KWLibMajorVersion = "2"
secureNetLib.KWLibMinorVersion = "0"


-- references to the data card and the network card
-- the library assumes we have both, since both are needed for it to work
secureNetLib.dataCard       = component.data
secureNetLib.networkCard    = component.modem

-- CONSTANTS
-- key length to use in comms
secureNetLib.KEY_LENGTH = 384
secureNetLib.CONTACT_BOOK_FILE_LOCATION = "/home/SecureNetContacts.dat"

-- list of trust levels for information-sharing decisions
-- you can modify it in runtime to define your own clearance/restriction levels, as it is only used locally
secureNetLib.trustLevels = {
    [0]  = "full_access",
    [1]  = "clearance_lvl_1",
    [2]  = "clearance_lvl_2",
    [3]  = "clearance_lvl_3",
    [4]  = "clearance_lvl_4",
    [-1] = "no_access"
}

-- list of possible states that the given contact can be in
secureNetLib.contactStates = {
    [-1] = "contact_blocked"
    [0]  = "contact_unknown"
    [1]  = "handshake_request"
    [2]  = "key_exchange"
    [3]  = "connected"
    [4]  = "keys_expired"
}

-- list of types of packets that can always be expected to be used
secureNetLib.packetTypes = {
    [0]  = "handshake_request"
    [1]  = "ACK"  -- also handshake affirm
    [-1] = "NACK" -- also handshake deny
    [2]  = "key_renewal"
    [-2] = "drop_connection"
    [3]  = "clearance_request"
}

-- contact template
function secureNetLib.getContactTemplate()
    local contactTemplate = {}

    contactTemplate.address         = nil
    contactTemplate.port            = nil
    contactTemplate.remotePublicKey = nil
    contactTemplate.iV              = nil

    contactTemplate.localKeyPair = {}
    contactTemplate.localKeyPair.private = nil
    contactTemplate.localKeyPair.public  = nil

    contactTemplate.trustLevel          = -1
    contactTemplate.loggedInTrustLevel  = -1
    contactTemplate.credentials  = {}
    contactTemplate.credentials.username_md5 = nil
    contactTemplate.credentials.password_md5 = nil
    contactTemplate.contactState = 0

    return contactTemplate
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

function secureNetLib.getNACKPacket(self)
    local NACK = self.getPacketTemplate()
    NACK.header.type = -1
    return NACK
end

function secureNetLib.getACKPacket(self)
    local ACK = self.getPacketTemplate()
    ACK.header.type = 1
end

-- handshake procedure:
-- 1) handshake request is received with type = 0, pK and iV filled and contact name in data
-- 2) address list is checked to verify remoteAddress is not blocked. NACK is sent if it is blocked
-- 3) contact template is generated and filled with the available information
-- 4) local storage is checked for credentials and logged-in trust level. contact is updated with this info if it exists
-- 5) new key pair is generated for the contact and added to the table
-- 6) contact is updated to state of key exchange
-- 7) ACK is sent with local name as data
function secureNetLib.onHandshakeRequest(self, remoteAddress, port, deserializedPacket, localName)
    -- check for blacklisting
    if type(self.contactBook[remoteAddress]) == "table" and self.contactBook[remoteAddress].contactState == -1 then
        modem.send(remoteAddress, port, serialization.serialize(self.getNACKPacket(self)))
        return false
    end

    -- generate new contact template
    local newContact = self.getContactTemplate()

    -- fill the template
    newContact.address          = remoteAddress
    newContact.port             = port
    newContact.remotePublicKey  = deserializedPacket.header.pK
    newContact.iV               = deserializedPacket.header.iV

    -- check storage for credentials
    --TBD

    -- generate new key pair and store it
    newContact.localKeyPair.public, newContact.localKeyPair.private = dataCard.generateKeyPair(self.KEY_LENGTH)

    -- update contact state
    newContact.contactState = 2

    -- generate ACK packet
    local ACK = self.getACKPacket(self)
    ACK.header.pK  = newContact.localKeyPair.public
    ACK.header.iV  = newContact.iV
    local encryptionKey = dataCard.md5(dataCard.ecdh(newContact.localKeyPair.private, newContact.remotePublicKey))
    ACK.body.data  = dataCard.encrypt(serialization.serialize(localName), encryptionKey, newContact.iV)
    ACK.footer.md5 = dataCard.md5(localName)

    -- send ACK
    modem.send(remoteAddress, port, serialization.serialize(ACK))

    -- add address to the list
    self.contactBook[deserializedPacket.body.data] = newContact
    return true
end

function secureNetLib.removeContact(self, contactName)
    self.contactBook[contactName] = nil
    return true
end


function secureNetLib.initializeLibrary(self, KWLib)
    io.write("OCSecureNetLib checking KWLib version compatibility: ")
    if not KWLib.checkVersionCompat(KWLib, self.KWLibMajorVersion, self.KWLibMinorVersion) then return false end
    io.write("KWLib compatible\n")
    self.KWLib = KWLib
    return true
end
return secureNetLib