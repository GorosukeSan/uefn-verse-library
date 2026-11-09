# Role: treats several cancelables as one cancelable. Pass them in Cancelables when creating it, or add them later with Add. Cancel cancels all of them at once (does nothing the second time and later)
cancelable_group<public> := class(cancelable):

    # Passed at creation: the cancelables to Cancel together (use Add for ones added later)
    Cancelables<public>:[]cancelable = array{}

    var<private> Added:[]cancelable = array{}
    var<private> Canceled:logic = false

    # Add one later. If already Canceled, the added one is Canceled on the spot
    Add<public>(Cancelable:cancelable)<transacts>:void =
        if (Canceled?):
            Cancelable.Cancel()
        else:
            set Added += array{Cancelable}

    Cancel<override>()<transacts>:void =
        if (Canceled?):
            return
        set Canceled = true
        for (Cancelable : Cancelables + Added):
            Cancelable.Cancel()

# Cancels the content if there is one. Does nothing if false
(Subscription:?cancelable).CancelIfSet<public>()<transacts>:void =
    if (Active := Subscription?):
        Active.Cancel()
