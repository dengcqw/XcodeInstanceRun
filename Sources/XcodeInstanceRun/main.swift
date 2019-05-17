import Foundation
import Commandant

let commands = CommandRegistry<CommandError>()
commands.register(BuildCommand())
commands.register(RunCommand())
commands.register(CopyCommand())
commands.register(DeployCommand())
commands.register(BuildBridgingheaderCommand())

let helpCommand = HelpCommand(registry: commands)
commands.register(helpCommand)
commands.main(defaultVerb: "help") { error in
    fputs("\(error)\n", stderr)
}
