module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Html as H exposing (Html)
import Html.Attributes as A
import Html.Events exposing (on, onInput, onClick)
import Http
import Json.Decode as D -- exposing (Decoder, field, string)
import Json.Encode as Encode exposing (Value)
import Url exposing (Url)
import Url.Parser as P exposing (Parser, (</>), int, map, oneOf, s, string)
import Url.Parser.Query as Q
import SingleDatePicker as DP
import Time as Time
import Task as Task
import Iso8601 as Iso8601

type State
    = WaitingForInput String
    | Loading
    | Failure
    | ViewEventState Event
    | NewEventState { picker: DP.DatePicker, input: EventInput }

type alias PageState = { key: Nav.Key
                       , state: State
                       }

type alias EventInput =
  { title          : String
  , description    : String
  , startTime      : Time.Posix
  , endTime        : Time.Posix
  , location       : String
  -- , googleMapsLink : Maybe String
  }

emptyEventInput : Time.Posix -> Time.Posix -> EventInput
emptyEventInput startTime endTime = { title = ""
                  , description = ""
                  , location = ""
                  , startTime = startTime
                  , endTime = endTime
                  }

encodeEventInput : EventInput -> Value
encodeEventInput { title, description, location, startTime, endTime } = Encode.object
                                                      [ ("title", Encode.string title)
                                                      , ("description", Encode.string description)
                                                      , ("location", Encode.string location)
                                                      , ("startTime", Iso8601.encode startTime)
                                                      , ("endTime", Iso8601.encode endTime)
                                                      ]

type alias Event =
  { id : String
  , title          : String
  , description    : String
  , startTime      : Time.Posix
  , endTime        : Time.Posix
  , location       : String
  , attendees      : List Attendee
  -- , googleMapsLink : Maybe String
  }

type alias Attendee =
  { firstName : String
  , lastName : String
  , status : AttendeeStatus
  , plusOne : Bool
  }

type AttendeeStatus
  = Coming
  | MaybeComing
  | NotComing


eventDecoder : D.Decoder Event
eventDecoder = D.map7 Event
                 (D.field "id" D.string)
                 (D.field "title" D.string)
                 (D.field "description" D.string)
                 (D.field "startTime" Iso8601.decoder)
                 (D.field "endTime" Iso8601.decoder)
                 (D.field "location" D.string)
                 (D.field "attendees" (D.list attendeeDecoder))

attendeeDecoder : D.Decoder Attendee
attendeeDecoder = D.map4 Attendee
                    (D.field "firstName" D.string)
                    (D.field "lastName" D.string)
                    (D.field "status" attendeeStatusDecoder)
                    (D.field "plusOne" D.bool)

attendeeStatusDecoder : D.Decoder AttendeeStatus
attendeeStatusDecoder =
  D.string
    |> D.andThen (\str ->
        case str of
          "Coming" -> D.succeed Coming
          "MaybeComing" -> D.succeed MaybeComing
          "NotComing" -> D.succeed NotComing
          somethingElse -> D.fail ("Unknown status: " ++ somethingElse)
      )

attendeeStatusToString : AttendeeStatus -> String
attendeeStatusToString status = case status of
                                  Coming -> "Coming"
                                  MaybeComing -> "Maybe Coming"
                                  NotComing -> "Not Coming"

-- view : State -> Html Msg
view : PageState -> Browser.Document Msg
view state =
  let
    updatePicker : EventInput -> ( DP.DatePicker, Maybe Time.Posix ) -> Msg
    updatePicker input (picker, mTimestamp) = case mTimestamp of
                                                  Just timestamp -> UpdateEventInput picker { input | startTime = timestamp }
                                                  Nothing -> UpdateEventInput picker input
  in
    Browser.Document "foo" [
      case state.state of
          WaitingForInput eventId ->
              H.div []
              [ H.input [ A.value eventId, onInput SetId ] []
              , H.button [ onClick (GetCat eventId) ] [ H.text "Submit"] ]

          Loading ->
              H.text "loading..."

          Failure ->
              H.text "failed to fetch new cat image"

          ViewEventState {title, description, startTime, endTime, location, attendees} ->
            H.div [] [ H.div [] [ H.h1 [] [ H.text title ] ]
                     , H.div [] [ H.text ("starts at: " ++ Iso8601.fromTime startTime) ]
                     , H.div [] [ H.text ("ends at: " ++ Iso8601.fromTime endTime) ]
                     , H.div [] [ H.text location ]
                     , H.div [] [ H.text description ]
                     , H.table []
                        ( H.tr [] [ H.th [] [ H.text "Name" ], H.th [] [ H.text "Coming?" ], H.th [] [ H.text "Plus One?" ] ]
                        :: (List.map (\{firstName, lastName, status, plusOne} -> H.tr [] [ H.td [] [ H.text (firstName ++ " " ++ lastName) ]
                                                                                         , H.td [] [ H.text (attendeeStatusToString status) ]
                                                                                         , H.td [] [ H.text (if plusOne then "Yes" else "No") ]
                                                                                         ]) attendees)
                        )
                     ]

          NewEventState { picker, input } -> H.div [] [
              H.h3 [] [ H.text "Create A New Event" ]
              , H.div [] [ H.text "Title: ", H.input [ A.value input.title, onInput (\t -> UpdateEventInput picker { input | title = t }) ] [] ]
              , H.div [] [ H.text "Description: ", H.input [ A.value input.description, onInput (\d -> UpdateEventInput picker { input | description = d }) ] [] ]
              , H.div [] [ H.button [ onClick OpenPicker ] [ H.text "click me" ], DP.view  (DP.defaultSettings Time.utc (updatePicker input)) picker ]
              -- , H.div [] [ H.text "Start Time: ", H.input [ A.type_ "datetime-local",  A.value input.startTime, onInput (\t -> UpdateEventInput { input | startTime = t })  ] [] ]
              -- , H.div [] [ H.text "End Time: ", H.input [ A.type_ "datetime-local" ] [] ]
              , H.div [] [ H.text "Location: ", H.input [] [] ]
              , H.button [ onClick (CreateEventMsg input) ] [ H.text "Submit" ]
            ]
    ]


fetchEvent : String -> Cmd Msg
fetchEvent id =
    Http.get
        { url = "http://localhost:8081/api/v1/events/" ++ id
        , expect = Http.expectJson GotResult eventDecoder
        }

createNewEvent : EventInput -> Cmd Msg
createNewEvent input = Http.post
                      { url = "http://localhost:8081/api/v1/events"
                      , expect = Http.expectJson GotResult eventDecoder
                      , body = Http.jsonBody (encodeEventInput input)
                      }

init : () -> Url -> Nav.Key -> ( PageState, Cmd Msg )
init _ url key =
  let
    (state, cmd) = case P.parse routeParser url of
                       Just NewEvent -> ( Loading, Task.perform CurrentTimeIs Time.now )
                       -- Just NewEvent -> ( NewEventState { picker = DP.init, input = emptyEventInput }, Cmd.none )
                       Just (EventId id) -> ( Loading, fetchEvent id )
                       Nothing -> ( Failure, Cmd.none )
  in ( { key = key, state = state }, cmd )

type Msg
    = GotResult (Result Http.Error Event)
    | GetCat String
    | SetId String
    | UrlRequest Browser.UrlRequest
    | UrlChange Url
    | UpdateEventInput DP.DatePicker EventInput
    | CreateEventMsg EventInput
    -- | UpdatePicker ( DP.DatePicker, Maybe Time.Posix )
    | OpenPicker
    | CurrentTimeIs Time.Posix



update : Msg -> PageState -> ( PageState, Cmd Msg )
update msg { key, state } =
    let
        (nextState, cmd) =
            case msg of
                SetId id -> ( WaitingForInput id, Cmd.none )
                GetCat id -> ( Loading, (fetchEvent id) )
                GotResult result ->
                    case result of
                        Ok event ->
                            ( ViewEventState event, Nav.pushUrl key ("/e/" ++ event.id) )

                        Err _ ->
                            ( Failure, Cmd.none )
                UrlRequest _ -> ( state, Cmd.none )
                UrlChange _ -> ( state, Cmd.none )
                UpdateEventInput picker input -> (NewEventState { picker = picker, input = input }, Cmd.none )
                CreateEventMsg input -> ( Loading, createNewEvent input )
                CurrentTimeIs time -> case state of
                                          -- NewEventState { picker, input } -> ( Loading , createNewEvent { input | startTime = Just time, endTime = Just time } )
                                          Loading -> ( NewEventState { picker = DP.init, input = emptyEventInput time time }, Cmd.none )
                                          _ -> ( state, Cmd.none)
                OpenPicker -> case state of
                                NewEventState x -> ( NewEventState { x | picker = x.picker }, Cmd.none )
                                _ -> ( state, Cmd.none )
    in
      ( { key = key, state = nextState }, cmd )



routeParser : Parser (Route -> a) a
routeParser = oneOf
    [ P.map NewEvent P.top
    , P.map EventId (s "e" </> string)
    ]

type Route = NewEvent
           | EventId String

main =
    Browser.application
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.none
        , view = view
        , onUrlRequest = UrlRequest
        , onUrlChange = UrlChange
        }
