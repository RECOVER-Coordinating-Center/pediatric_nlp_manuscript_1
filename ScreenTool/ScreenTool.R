#  Version 7.2 of ScreenTool  5/8/25

library(shiny)
library(stringr)
library(dplyr)

#
# Set up table of users and passwords. Lists of entities to be screened are
# stored in CSV files with the username as the file basename. The user and
# password lists are just ordered lists that can be edited to add new users
# and corresponding passwords. Since the passwords are stored here in plain
# text it is not obvious what the encryption is buying us...
#
user_base <- tibble::tibble(
  user = c("exampleuser", "egUser2"),
  password = purrr::map_chr(c("examplepass","egUser2Pass"), sodium::password_store)
)


# login tab ui to be rendered on launch
login_tab <- tabPanel(
  title = icon("lock"), 
  value = "login", 
  shinyauthr::loginUI("login")
)

#
# Highlight the recognized entity in the context text
# This assumes that the context is 201 characters starting 100 chars before 
# the start of the entity and extending 100 characters after the start of
# the entity (does not take length of entity into account)
#
highlight <- function(text, beg, end) {
  nc <- end - beg + 1
  if (beg > 1)
    a <- substr(text,1,beg-1)
  else
    a <- ""
  b <- substr(text, beg, end)
  if (end < str_length(text))
    c <- substr(text, end+1, str_length(text))
  else
    c <- ""
  paste0(a,"<b><mark>",b,"</mark></b>",c)
}
#
# A dataframe called "user_df" accumulates the SME responses. The saveData
# function will append the current response to "user_df" or start a new frame
# if it does not exist. Note that this dataframe is in the global environment
# of the process that launched the screening tool.
#
saveData <- function(data, user, user_df, action="A") {
  if (action == "A") {
    user_df <- rbind(user_df, data)
  }
  saveRDS(user_df,paste0(user,'_screen_tool.rds'))
  user_df
}
#
# Returns the existing response data frame. This function is used prior to
# saving the responses to a local file.
#
#loadData <- function() {
#  if (exists('user_df')) {
#    user_df
#  }
#}

#
# Define UI for Screening Tool ----
# changed this to be a tab so it can be added after the successful login
# was one of the easier ways to get it running as I wanted isn't the cleanest
# but can be changed as well (Comment from A.S.)
#
screen_tool <- tabPanel(
  
  # App title ----
  titlePanel('NER Screening Tool'),
  sidebarLayout(
    sidebarPanel(
      fluidRow(column(12, h4(textOutput('idx')))),
      fluidRow(
        column(6, radioButtons("func", "Relevance to Concept",
                               c("Related" = "related",
                                 "Unrelated" = "unrelated"
                                ))),
        column(6, radioButtons("asrt", "Assertion",
                               c("Present" = "present",
                                 "Absent" = "absent",
                                 "Hypothetical" = "hypothetical",
                                 "Past" = "past",
                                 "Other" = "other"
                                 )))
      ),
      fluidRow(
        column(3,actionButton('abs', 'Abstain')),
        column(3," "),
        column(3,actionButton('subm', 'Submit'))
      ),
      hr(),
      hr(),
      fluidRow(
        column(4,actionButton('end','End Session'))
      )
    ),
    mainPanel(
      fluidRow(
        column(3,h3('Concept: ')),
        column(9, h3(textOutput('concept')))
      ),
      hr(),
      fluidRow(
        column(12,htmlOutput('ctx_text'))
      ),
      hr(),
      fluidRow(
        column(12,textAreaInput('cmmt',"Comments/Notes", width="100%"))
      )
    )
  )
)

#starts the app with just the login page
ui <- navbarPage(
  title = "NER Screening Tool LOGIN",
  id = "tabs", # must give id here to add/remove tabs in server
  collapsible = TRUE,
  login_tab,
  screen_tool
)

#
# Main server function for screening tool. First handles login of the SME and
# then administers the list of items to be screened. Logic is provided to save
# state and return later to the task to complete the list.
#
server <- function(input, output, session) {
  #this is how the app will use the credentials to handle the login
  credentials <- shinyauthr::loginServer(
    id = "login",
    data = user_base,
    user_col = "user",
    pwd_col = "password",
    sodium_hashed = TRUE,
    reload_on_logout = TRUE,
    log_out = reactive(logout_init())
  )
  
  logout_init <- shinyauthr::logoutServer(
    id = "logout",
    active = reactive(credentials()$user_auth)
  )

  user_data <- list()
  observeEvent(credentials()$user_auth, {
    # if user logs in successfully
    # this runs thru the code base that was originally in do_Screen.r
    # i.e., it takes the user name and creates the csv filename then 
    # the rds filename. Then reads the input csv and the prior .rds file
    # if one exists. (comment by A.S.)
    if (credentials()$user_auth) { 
      user <- credentials()$info$user
      userFile <- paste0(user, ".csv")
      if (!file.exists(userFile)) {
        stopApp(paste0("User input file ",userFile," not found!"))
      }
      print(userFile)
      cat("Reading NER table...")
      script.df <- read.csv(userFile)
      end_idx <- nrow(script.df)
      cat("done.\n")
      #
      # SMEs are allowed to leave the application and return later to finish
      # their assigned set of entities to screen. If they are returning from 
      # a previous session, the <username>_screen_tool.rds file will exist
      # and will be used to populate the user dataframe before the SME
      # continues the session.
      #
      savedFile <- paste0(user,"_screen_tool.rds")
      if (file.exists(savedFile)) {
        user_df <- readRDS(savedFile)
        print(paste0("input nrow = ", nrow(user_df)," input length = ", length(user_df)))
        if (length(user_df) > 0) {
          if (nrow(user_df) > 0) {
            if (ncol(user_df) == 3) {  # Old format: add cmmt field
              user_df$cmmt=""
            }
          }
        } else {  # Exists, but empty!
          print("Data file exists, but seems to be empty!")
          user_df <- data.frame(idx=integer(), func=character(), asrt=character(),
                                  cmmt=character())
        }
      } else {
        user_df <- data.frame(idx=integer(), func=character(), asrt=character(),
                                cmmt=character())
      }
      start_idx <- nrow(user_df) + 1
      cat("Starting screening tool at index ",start_idx,"\n")
      idx <- start_idx
      # This removes the login tab and adds the actual screening tool as a tab
      # it has to be clicked to continue (comment by A.S.)
      removeTab("tabs","login")
#      appendTab("tabs", screen_tool)
      
      # Here is the remainder of the logic that will actually run the app
      # it needed to be here or will get rendered before the values above 
      # start_idx and the script.df were created
      # this was breaking things so had to put it here
      # I assume this is where any logic change or any other functions would be
      # called (comment by A.S.)
      
      v <- reactiveValues(idx=start_idx, func="", asrt="", cmmt="", user_df=user_df,
                          oldt=as.integer(Sys.time()))

      #
      # Handle press of Submit button
      #
      observeEvent(input$subm, {
        newt = as.integer(Sys.time())
        if ((newt - v$oldt) > 4) {
          rec <-  data.frame(idx=v$idx, func=input$func, asrt=input$asrt, cmmt=input$cmmt)
          v$idx <- v$idx + 1
          v$user_df = saveData(rec, user, v$user_df)
          updateRadioButtons(session, 'func', selected="related")
          updateRadioButtons(session, 'asrt', selected="present")
          updateTextAreaInput(session, "cmmt", value="")
#         if (v$idx > end_idx) {
#            stopApp(paste0(end_idx," tokens completed. No more to do!" ))
#         }
        }
        v$oldt = newt
      })
      #
      # Handle Abstain button
      #
      observeEvent(input$abs, {
        newt = as.integer(Sys.time())
        if ((newt - v$oldt) > 4) {
          rec <-  data.frame(idx=v$idx, func="abstain", asrt=input$asrt, cmmt=input$cmmt)
          v$idx <- v$idx + 1
          v$user_df = saveData(rec, user, v$user_df)
          updateRadioButtons(session, 'func', selected="related")
          updateRadioButtons(session, 'asrt', selected="present")
          updateTextAreaInput(session, "cmmt", value="")
#         if (v$idx > end_idx) {
#            stopApp(paste0(end_idx," tokens completed. No more to do!" ))
#         }
        }
        v$oldt = newt
      })
      #
      # Handle End button (load collected data, save to file, end app)
      #
      observeEvent(input$end, {
#        screen_tool.df <- loadData()
#        saveRDS(user_df,paste0(user,'_screen_tool.rds'))
        stopApp(paste0((v$idx - 1)," tokens completed."))
      })
      #
      #      Update screen for next trial
      #
      # Note that controls are updated above following using input. Here we
      # display the next concept in the header.
      #
     
        output$concept <- renderText({ ifelse(v$idx > end_idx, "List Completed!", script.df$concept[v$idx])
      })
      #
      # Render the context text and highlight the entity within the text.
      #
        output$ctx_text <- renderUI({ HTML(ifelse (v$idx > end_idx,
          "<b><mark>Press End Session to close this window.</mark></b>",
          highlight(script.df$text[v$idx],
                         script.df$token_start[v$idx],
                         script.df$token_end[v$idx])))})
      #
      # Update onscreen trial counter
      #
      output$idx <- renderText({paste('Trial Number:',v$idx,' of ',end_idx)})
      cat("idx=",v$idx,"\n")
    }
  })

}

#
# This is the initial function to fire up the tool.
#
shinyApp(ui = ui, server = server)
