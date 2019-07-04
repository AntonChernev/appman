# Appman

Elixir applications manager

## Prerequisites
To run an application with Appman, add *https://github.com/AntonChernev/appman_dep*
as a dependency to your project.

## Operations description

Appman must be given a node name to work properly.
Write permission must be granted for **/var/logs/appman** for the logs to work.

### Register
Applications must be registered before they can be started.
They are given a name and a path to the project directory.

### List
Shows every registered application with its path and status.
Status can be :registered, :initializing or :running.

### Start
Tries to start an application with status :registered.
A script that starts the application in a new node is executed.
Status changes to :initializing.
The new application starts a Connector process that communicates with Appman Manager.
Connector sends a node_running message to confirm the successful initialization.
Manager receives the message and sends its pid to Connector.
Status changes to :running.
If Manager doesn't receive a node_running message, initialization will fail with timeout.
Manager monitors the application node and Connector monitors the Manager process.
If Connector dies, the user is notified.
If Manager dies, Connector stops the application.

### Stop
Tries to stop a running application.
Manager asks Connector to stop the application.
If Connector stops successfully, Manager will receive a monitor message and
show that the application is stopped.
If the stop is a part of a restart command, Manager will start the application again.

### Restart
Tries to stop a running application and marks it for consequent start.

### Logs
Finds a log file for an application and prints its last lines.
Log file names follow a convention and can be found by the name of the application.
