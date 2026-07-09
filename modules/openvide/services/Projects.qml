pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components

Singleton {
    id: root

    property string mode: "new"
    property string step: "project"
    property string query: ""
    property string selectedRepo: ""
    property string selectedBranch: ""
    property var screenState
    property var items: []

    readonly property bool showList: step !== "folder" && step !== "branchName"
    readonly property string helper: `${Quickshell.shellDir}/assets/openvide.sh`
    readonly property string placeholder: {
        if (step === "switch")
            return qsTr("Switch set");
        if (step === "repo")
            return qsTr("Repo worktree");
        if (step === "branch")
            return qsTr("Branche");
        if (step === "folder")
            return qsTr("Nom dossier");
        if (step === "branchName")
            return qsTr("Nouvelle branche");
        return qsTr("Projet");
    }
    readonly property var filteredItems: {
        const q = query.toLowerCase();
        if (q.length === 0)
            return items;
        return items.filter(item => item.label.toLowerCase().indexOf(q) !== -1);
    }

    function open(newMode: string, newScreenState: ScreenState): void {
        mode = newMode;
        screenState = newScreenState;
        step = mode === "switch" ? "switch" : "project";
        selectedRepo = "";
        selectedBranch = "";
        load();
    }

    function reset(): void {
        query = "";
        items = [];
    }

    function commandForStep(): list<string> {
        if (step === "switch")
            return ["bash", helper, "--list-sets"];
        if (step === "repo")
            return ["bash", helper, "--list-repos"];
        if (step === "branch")
            return ["bash", helper, "--list-branches", selectedRepo];
        return ["bash", helper, "--list-projects"];
    }

    function load(): void {
        query = "";
        items = [];
        listProc.exec(commandForStep());
    }

    function run(args: list<string>, screenState: ScreenState): void {
        screenState.openvide = false;
        Quickshell.execDetached(["bash", helper, ...args]);
    }

    function accept(item: var, screenState: ScreenState): void {
        if (step === "branchName") {
            if (query.length === 0)
                return;
            selectedBranch = query;
            step = "folder";
            query = selectedBranch;
            return;
        }

        if (step === "folder") {
            run(["--create-worktree", selectedRepo, selectedBranch, query.length === 0 ? selectedBranch : query], screenState);
            return;
        }

        if (!item)
            return;

        if (step === "switch") {
            run(["--switch-set", item.value], screenState);
        } else if (step === "project" && item.value === "__new_worktree__") {
            step = "repo";
            load();
        } else if (step === "project") {
            run(["--open-project", item.value], screenState);
        } else if (step === "repo") {
            selectedRepo = item.value;
            step = "branch";
            load();
        } else if (step === "branch" && item.value === "__new_branch__") {
            step = "branchName";
            query = "";
        } else if (step === "branch") {
            selectedBranch = item.value;
            step = "folder";
            query = selectedBranch;
        }
    }

    function goBack(screenState: ScreenState): void {
        if (step === "project" || step === "switch") {
            screenState.openvide = false;
        } else if (step === "repo") {
            step = "project";
            load();
        } else if (step === "branch" || step === "branchName" || step === "folder") {
            step = step === "branch" ? "repo" : "branch";
            load();
        }
    }

    Process {
        id: listProc

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) {
                    root.items = [];
                    return;
                }

                try {
                    const parsed = JSON.parse(text);
                    if (root.step === "switch" && parsed.length === 1 && root.screenState) {
                        root.accept(parsed[0], root.screenState);
                        root.items = [];
                    } else {
                        root.items = parsed;
                    }
                } catch (error) {
                    root.items = [];
                    console.log("openvide parse error: " + error);
                }
            }
        }
    }
}
