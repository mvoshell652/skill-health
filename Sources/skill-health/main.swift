import Foundation
import SkillHealthCore

// Skill Health, the Claude Code plugin's command-line tool (plugin/bin/skill-health). The plugin's commands
// (/skill-health:check, fix, update, undo) do their work through it, with the same engine the Mac app
// uses, so every guard on a write is the one the app's tests prove. It writes a skill only through
// an `apply` command, after a `preview` made a plan; the plugin's gate hook makes Claude Code ask
// the person, showing that plan, before an apply runs.
//
// SKILL_HEALTH_CLAUDE_HOME points it at another .claude folder (tests); SKILL_HEALTH_CORRECTIONS at another
// known-corrections file. Errors go to stderr as "skill-health: <what to do>", exit 1; usage errors exit 2.

let arguments = Array(CommandLine.arguments.dropFirst())
let tool = Tool(arguments: arguments)

do {
    switch arguments.first {
    case "version": tool.version()
    case "status": await tool.status()
    case "findings": try await tool.findings()
    case "fix": try await tool.fix()
    case "decide": try await tool.decide()
    case "issue": try await tool.issue()
    case "undo": try await tool.undo()
    case "update": try await tool.update()
    case "compare": try await tool.compare()
    case "plan": await tool.plan()
    case "save-findings": try await tool.saveFindings()
    case "refresh": await tool.refresh()
    case "usage": try await tool.usage()
    case "export-shared": try await tool.exportShared()
    default:
        Tool.usageError("""
            usage: skill-health <command>
              status [--json]                     what Skill Health knows now
              refresh                             bring up to date what Claude gets at the start of a session
              findings [skill] [--json]           failing and deprecated instructions to go through
              fix preview <finding> [--with -]    show the change to one line (replacement on stdin with --with -)
              fix apply <plan>                    write it (Claude Code asks you first)
              decide <finding> set-aside 30|90|until-update | another <skill> | reopen
              issue <finding> [--open]            draft an issue for the skill's author
              undo list [--json] | preview <entry> | apply <plan>
              update list [--json] | preview <skill>...|--all | apply <plan>
              compare                             compare skills with their sources on GitHub now
              plan [--json]                       what /skill-health:check can check
              save-findings -                     save a check's results (JSON on stdin)
              version
            """)
    }
    // What Claude gets at the start of the next session follows what this command just changed.
    if tool.changesWhatClaudeGets {
        fflush(stdout)   // the command's answer shouldn't wait for the refresh
        await tool.refreshQuietly()
    }
} catch let error as SkillHealthError {
    Tool.fail(error.plainDescription.droppingErrorPrefix)
} catch {
    Tool.fail(error.localizedDescription)
}
