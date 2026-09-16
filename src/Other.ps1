# python venv
function tovenv {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
    & ./.venv/Scripts/Activate.ps1
}


function Open-Profile {
    code $PROFILE
}