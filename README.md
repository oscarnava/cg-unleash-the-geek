# Unleash the geek

### Codingame.com contest (4/Oct/2019)

This is the code I developed during the contest **Unleash the geek** on [Codingame](http://www.codingame.com/). I used Ruby mainly because currently, I'm still learning the language while participating in the [Microverse](http://www.microverse.org/) training program.

#### [View Ruby leaderboard](https://www.codingame.com/leaderboards/contests/unleash-the-geek-amadeus/global?column=language&value=Ruby)

## Main points to consider :

* All the design is separated in classes, being **GameState** the main class. 
* Only one instance of **GameState** exists, and each turn it's updated and asked for the next moves.
* Entities like *Robots*, *Traps*, and *Radars* all derive from the parent class **Entity**, and robot strategies derive from the class **Task**.
* Each robot is assigned a task, which will depend on the current state of the game.
* When finished a task, robots are assigned another one depending on its current state.
* Radar positions are fixed trying to maximize the area covered and the probability of being in the range of an ore vein.
* The class **Command** is private to GameState so that the later can be updated every time a robot computes the command it will issue.
* When created, a **Position**'s row and column will be coerced to be laid within the board.
* Each **Cell** instance contains the current state of the corresponding cell on the board, even some guessed features like *"Is it dangerous? (probable enemy trap)"* or *"Was it dug just now?"*
