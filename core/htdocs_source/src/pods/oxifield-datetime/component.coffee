`import Em from "vendor/ember"`
`import moment from "vendor/moment"`

Component = Em.Component.extend
    format: "DD.MM.YYYY HH:mm"

    options: {}

    setup: Em.on "didInsertElement", ->
        value = @get "content.value"
        if value is "now"
            @set "content.pickvalue", moment().utc().format @get "format"
        else if value
            @set "content.pickvalue", moment.unix(value).utc().format @get "format"
        Em.run.next =>
            @$().find(".date").datetimepicker
                format: @get "format"

    propagate: Em.observer "content.pickvalue", ->
        if @get("content.pickvalue")
            datetime = moment.utc(@get("content.pickvalue"), @get("format")).unix()
        else
            dateimte = ""
        @set "content.value", datetime

`export default Component`
