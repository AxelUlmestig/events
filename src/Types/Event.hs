module Types.Event (Event(..), Attendee) where

import           Data.Aeson            (ToJSON)
import           Data.Text             (Text)
import           Data.Time.Clock       (UTCTime)
import           Data.Types.Isomorphic (Injective (to), Iso)
import           Data.UUID             (UUID)
import           GHC.Generics          (Generic)
import           Types.Attendee        (AttendeeStatus (..), readStatus)

data Event = Event
           { id             :: UUID
           , title          :: Text
           , description    :: Text
           , startTime      :: UTCTime
           , endTime        :: Maybe UTCTime
           , location       :: Text
           , googleMapsLink :: Maybe Text
           , attendees      :: [Attendee]
           }
           deriving (Generic)

data Attendee = Attendee
                { name    :: Text
                , status  :: AttendeeStatus
                , plusOne :: Bool
                }
                deriving (Generic)

instance ToJSON Attendee
instance ToJSON Event

instance Injective (UUID, Text, Text, UTCTime, Maybe UTCTime, Text, Maybe Text) Event where
  to (id, title, description, startTime, endTime, location, googleMapsLink) = Event id title description startTime endTime location googleMapsLink []

instance Injective (Text, Text, Bool) Attendee where
  to (name, status, plusOne) = Attendee name (readStatus status) plusOne
